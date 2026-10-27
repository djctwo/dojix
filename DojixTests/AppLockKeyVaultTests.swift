import CryptoKit
import Security
import XCTest
@testable import Dojix

/// App Lock protects the data: the database key is wrapped with the lock password
/// (F1, F3, F4). Uses an in-memory store; the Keychain store is a thin adapter over it.
final class AppLockKeyVaultTests: XCTestCase {
    private let fast: UInt32 = 1_000 // test-only iteration count; the app uses 600,000

    private func raw(_ key: SymmetricKey) -> Data { key.withUnsafeBytes { Data($0) } }

    func testWrapRemovesBareKeyAndNeedsThePassword() throws {
        let store = MemorySecretStore()
        let vault = DatabaseKeyVault(store: store, iterations: fast)
        let key = try vault.createPlainKey()
        XCTAssertEqual(try vault.state(), .plain)

        try vault.wrap(key, password: "correct horse")

        XCTAssertEqual(try vault.state(), .wrapped)
        XCTAssertNil(store.value(DatabaseKeyVault.plainAccount), "the bare key must be gone once wrapped")
        let blob = try XCTUnwrap(store.value(DatabaseKeyVault.wrappedAccount))
        XCTAssertFalse(blob.contains(raw(key).base64EncodedString()), "the stored item must not contain the key")
        XCTAssertEqual(raw(try vault.unwrap(password: "correct horse")), raw(key))
        XCTAssertThrowsError(try vault.unwrap(password: "wrong horse")) {
            XCTAssertEqual($0 as? DatabaseKeyVault.VaultError, .wrongPassword)
        }
        XCTAssertTrue(AppLock.isEnabled(vault: vault))
    }

    func testDefaultIterationCountIsHigh() throws {
        XCTAssertEqual(DatabaseKeyVault.defaultIterations, 600_000)
        let blob = try DatabaseKeyVault.seal(SymmetricKey(size: .bits256), password: "pw-123456",
                                             iterations: DatabaseKeyVault.defaultIterations)
        XCTAssertEqual(DatabaseKeyVault.iterations(of: blob), 600_000)
        // Two wraps of the same key use different salts
        let again = try DatabaseKeyVault.seal(SymmetricKey(size: .bits256), password: "pw-123456", iterations: fast)
        XCTAssertNotEqual(Data(base64Encoded: blob)?[9..<25], Data(base64Encoded: again)?[9..<25])
    }

    func testRotationKeepsBothKeysUntilFinished() throws {
        let store = MemorySecretStore()
        let vault = DatabaseKeyVault(store: store, iterations: fast)
        let oldKey = try vault.createPlainKey()

        let newKey = try vault.beginRotation(from: oldKey, password: "first-password")
        XCTAssertNotEqual(raw(newKey), raw(oldKey), "a new key is generated")
        XCTAssertNil(store.value(DatabaseKeyVault.plainAccount), "the bare key is gone after the wrapped copy is stored")
        let pending = try vault.unwrapKeys(password: "first-password")
        XCTAssertEqual(raw(pending.current), raw(newKey))
        XCTAssertEqual(pending.previous.map(raw), raw(oldKey), "the old key stays (wrapped) until files are re-sealed")

        try vault.finishRotation(newKey, password: "first-password")
        let done = try vault.unwrapKeys(password: "first-password")
        XCTAssertEqual(raw(done.current), raw(newKey))
        XCTAssertNil(done.previous, "after the rotation only the new key is stored")
    }

    func testDisableLockUnwrapsBackToBareKey() throws {
        let store = MemorySecretStore()
        let vault = DatabaseKeyVault(store: store, iterations: fast)
        let key = try vault.createPlainKey()
        try vault.wrap(key, password: "lock-password")

        XCTAssertThrowsError(try vault.unwrapToPlain(password: "guess"))
        XCTAssertEqual(try vault.state(), .wrapped, "a wrong password changes nothing")

        try vault.unwrapToPlain(password: "lock-password")
        XCTAssertEqual(try vault.state(), .plain)
        XCTAssertNil(store.value(DatabaseKeyVault.wrappedAccount))
        XCTAssertEqual(raw(try XCTUnwrap(try vault.plainKey())), raw(key))
        XCTAssertFalse(AppLock.isEnabled(vault: vault))
    }

    func testLegacyLockIsMigratedAtFirstUnlock() throws {
        // An older build: bare key in the Keychain plus a separate password hash.
        let store = MemorySecretStore()
        let vault = DatabaseKeyVault(store: store, iterations: fast)
        let oldKey = try vault.createPlainKey()
        let legacyHash = PasswordHasher.hash("old-build-pass")
        store.write(DatabaseKeyVault.legacyHashAccount, legacyHash)
        XCTAssertTrue(AppLock.isEnabled(vault: vault))

        XCTAssertThrowsError(try AppState.unlockKeys(vault: vault, password: "nope", legacyHash: legacyHash)) {
            XCTAssertEqual($0 as? DatabaseKeyVault.VaultError, .wrongPassword)
        }
        XCTAssertEqual(try vault.state(), .plain, "nothing is migrated on a wrong password")

        let keys = try AppState.unlockKeys(vault: vault, password: "old-build-pass", legacyHash: legacyHash)
        XCTAssertNotEqual(raw(keys.current), raw(oldKey), "the migration rotates to a new key")
        XCTAssertEqual(keys.previous.map(raw), raw(oldKey), "the old key is kept until the journal is re-sealed")
        XCTAssertEqual(try vault.state(), .wrapped)
        XCTAssertNil(store.value(DatabaseKeyVault.plainAccount), "the bare key is removed")
        // From now on the password itself unwraps the keys (the old hash is not needed)
        XCTAssertEqual(raw(try AppState.unlockKeys(vault: vault, password: "old-build-pass", legacyHash: nil).current),
                       raw(keys.current))
    }

    func testBareKeyLeftNextToWrappedIsCleanedUp() throws {
        let store = MemorySecretStore()
        let vault = DatabaseKeyVault(store: store, iterations: fast)
        let key = try vault.createPlainKey()
        // Simulate: wrapped item written, process died before the bare key was deleted
        store.write(DatabaseKeyVault.wrappedAccount,
                    try DatabaseKeyVault.seal(keys: [SymmetricKey(size: .bits256), key], password: "pw-pw-pw-pw", iterations: fast))
        XCTAssertEqual(try vault.state(), .wrapped, "a wrapped key always means the lock is on")

        let keys = try AppState.unlockKeys(vault: vault, password: "pw-pw-pw-pw", legacyHash: nil)
        XCTAssertEqual(keys.previous.map(raw), raw(key), "the bare key is still available, wrapped")
        XCTAssertNil(store.value(DatabaseKeyVault.plainAccount))
    }

    func testNeverReplacesAnExistingKey() throws {
        let vault = DatabaseKeyVault(store: MemorySecretStore(), iterations: fast)
        _ = try vault.createPlainKey()
        XCTAssertThrowsError(try vault.createPlainKey())
    }

    func testUnreadableKeychainFailsClosed() {
        let store = MemorySecretStore()
        store.forcedReadStatus = errSecInteractionNotAllowed
        let vault = DatabaseKeyVault(store: store, iterations: fast)
        XCTAssertThrowsError(try vault.state())
        XCTAssertThrowsError(try vault.createPlainKey(), "never create a key over one that can't be read")
        XCTAssertTrue(AppLock.isEnabled(vault: vault))
    }

    func testTamperedWrappedKeyIsRejected() throws {
        let blob = try DatabaseKeyVault.seal(SymmetricKey(size: .bits256), password: "pw-123456", iterations: fast)
        var bytes = try XCTUnwrap(Data(base64Encoded: blob))
        // Lower the iteration count to 1: outside the accepted range
        bytes.replaceSubrange(5..<9, with: [0, 0, 0, 1])
        XCTAssertThrowsError(try DatabaseKeyVault.open(bytes.base64EncodedString(), password: "pw-123456")) {
            XCTAssertEqual($0 as? DatabaseKeyVault.VaultError, .corrupt)
        }
        // A changed header (authenticated data) fails like a wrong password
        var header = try XCTUnwrap(Data(base64Encoded: blob))
        header[10] ^= 0xFF
        XCTAssertThrowsError(try DatabaseKeyVault.open(header.base64EncodedString(), password: "pw-123456"))
    }
}
