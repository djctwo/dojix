import CryptoKit
import Foundation
import Security
import os

/// Where the vault keeps its two items. The app uses the Keychain; tests inject an
/// in-memory store so the wrapping logic can be exercised without touching a Keychain.
protocol SecretStore: Sendable {
    /// The stored value and the raw status (errSecItemNotFound = no such item).
    func read(_ account: String) -> (value: String?, status: OSStatus)
    /// Write or replace a value in place. Returns false if the store refused it.
    @discardableResult func write(_ account: String, _ value: String) -> Bool
    func delete(_ account: String)
}

/// The app's Keychain (service = `Configuration.keychainService`).
struct KeychainSecretStore: SecretStore {
    /// false: a write that would need macOS to ask the user (a locked keychain) fails
    /// instead of showing a dialog. Used where a failed write is tolerated (the save
    /// record), never for the key itself.
    var allowsUserInteraction = true

    func read(_ account: String) -> (value: String?, status: OSStatus) {
        KeychainHelper.readWithStatus(key: account)
    }

    @discardableResult
    func write(_ account: String, _ value: String) -> Bool {
        KeychainHelper.replace(key: account, value: value, allowsUserInteraction: allowsUserInteraction)
    }

    func delete(_ account: String) {
        KeychainHelper.delete(key: account)
    }
}

/// Holds the 256-bit key that encrypts the journal database (and screenshots).
///
/// - App Lock off: the key is a plain Keychain item (`database_encryption_key`).
/// - App Lock on: the key is stored only *wrapped* (AES-256-GCM) under a key derived
///   from the lock password with PBKDF2-SHA256 (600,000 iterations, random per-install
///   salt). Without the password nothing can be decrypted, so the lock protects the data
///   itself, not just the screen.
///
/// Every transition writes the new form first, reads it back and checks it opens to the
/// same key, and only then deletes the old form, so a crash never leaves no usable key.
struct DatabaseKeyVault: Sendable {
    static let plainAccount = "database_encryption_key"
    static let wrappedAccount = "database_key_wrapped"
    /// Password hash kept by builds before the key was wrapped (their App Lock).
    static let legacyHashAccount = "app_lock_hash"
    /// OWASP 2023 recommendation for PBKDF2-HMAC-SHA256.
    static let defaultIterations: UInt32 = 600_000
    /// Accepted range when reading a wrapped key (guards against a tampered item
    /// asking for zero work, or for hours of it).
    static let iterationRange: ClosedRange<UInt32> = 1_000...10_000_000

    private static let logger = Logger(subsystem: "com.dojix", category: "KeyVault")
    private static let magic = Data("DJXW".utf8)
    private static let formatVersion: UInt8 = 1

    let store: any SecretStore
    let iterations: UInt32

    init(store: any SecretStore = KeychainSecretStore(), iterations: UInt32 = DatabaseKeyVault.defaultIterations) {
        self.store = store
        self.iterations = iterations
    }

    enum State: Equatable, Sendable {
        /// No key yet (first launch, or after "erase all").
        case empty
        /// Bare key in the Keychain (App Lock off, or a lock set by an older build).
        case plain
        /// Key wrapped with the App Lock password.
        case wrapped
    }

    enum VaultError: LocalizedError, Equatable {
        case unreadable(OSStatus)
        case wrongPassword
        case corrupt
        case storeFailed
        case keyAlreadyExists
        /// A key rotation is still pending (two keys stored); it must be finished before
        /// the key or password changes again, or the older key would be lost.
        case rotationPending
        /// The Keychain accepted the new wrapped key but couldn't be read back right
        /// after, so the write isn't confirmed (it almost certainly took effect).
        case unconfirmed

        var errorDescription: String? {
            switch self {
            case .unreadable(let status): "The database key could not be read from the Keychain (status \(status))."
            case .wrongPassword: "Incorrect password."
            case .corrupt: "The stored database key is damaged."
            case .storeFailed: "The database key could not be saved to the Keychain."
            case .keyAlreadyExists: "A database key already exists."
            case .rotationPending:
                "Dojix hasn't finished re-encrypting some files with the current key yet, so nothing was changed. "
                    + "Make sure the Dojix data folder can be written to, then try again."
            case .unconfirmed: "The database key was saved to the Keychain but couldn't be read back to check it."
            }
        }
    }

    // MARK: - State

    func state() throws -> State {
        if try readItem(Self.wrappedAccount) != nil { return .wrapped }
        if try readItem(Self.plainAccount) != nil { return .plain }
        return .empty
    }

    /// The bare key, or nil if there is none.
    func plainKey() throws -> SymmetricKey? {
        guard let base64 = try readItem(Self.plainAccount) else { return nil }
        guard let data = Data(base64Encoded: base64), data.count == 32 else { throw VaultError.corrupt }
        return SymmetricKey(data: data)
    }

    /// Create the first key. Refuses if any key (plain or wrapped) already exists, so a
    /// real key is never replaced and the journal never lost.
    func createPlainKey() throws -> SymmetricKey {
        guard try state() == .empty else { throw VaultError.keyAlreadyExists }
        let key = SymmetricKey(size: .bits256)
        guard store.write(Self.plainAccount, Self.base64(key)) else { throw VaultError.storeFailed }
        Self.logger.info("Generated new database encryption key")
        return key
    }

    // MARK: - Wrap / unwrap

    /// The keys inside the wrapped item: the current key, plus the previous one while a
    /// key rotation is in progress (until every file has been re-sealed).
    struct UnwrappedKeys: Sendable {
        let current: SymmetricKey
        let previous: SymmetricKey?
    }

    /// Unwrap with the App Lock password. Throws `.wrongPassword` for a wrong password.
    func unwrapKeys(password: String) throws -> UnwrappedKeys {
        guard let blob = try readItem(Self.wrappedAccount) else { throw VaultError.corrupt }
        let keys = try Self.open(blob, password: password)
        return UnwrappedKeys(current: keys[0], previous: keys.count > 1 ? keys[1] : nil)
    }

    /// The current key (see `unwrapKeys`).
    func unwrap(password: String) throws -> SymmetricKey {
        try unwrapKeys(password: password).current
    }

    /// Step 1 of a key rotation (App Lock turned on, password changed, or a lock set by
    /// an older build migrated): create a NEW key and store it wrapped with `password`
    /// together with `oldKey`, then delete the bare key. Nothing is lost if the process
    /// stops at any point: until `finishRotation`, the wrapped item still holds the old
    /// key, so files not yet re-sealed stay readable.
    /// Throws `rotationPending` if an earlier rotation is unfinished (two keys stored):
    /// overwriting it would drop that rotation's old key while files may still need it.
    /// Throws `unconfirmed` (bare key kept) if the new item couldn't be read back.
    func beginRotation(from oldKey: SymmetricKey, password: String) throws -> SymmetricKey {
        guard try !hasPendingRotation() else { throw VaultError.rotationPending }
        let newKey = SymmetricKey(size: .bits256)
        try writeWrapped(keys: [newKey, oldKey], password: password)
        store.delete(Self.plainAccount)
        return newKey
    }

    /// Last step of a key rotation, once the journal and every file are sealed with
    /// `key`: store only `key`, wrapped. The old key is gone from the Keychain.
    func finishRotation(_ key: SymmetricKey, password: String) throws {
        try writeWrapped(keys: [key], password: password)
        store.delete(Self.plainAccount)
    }

    /// Wrap `key` alone with `password` and remove the bare key (no rotation).
    func wrap(_ key: SymmetricKey, password: String) throws {
        try finishRotation(key, password: password)
    }

    /// Turn App Lock off: after the password checks out, store the key bare again and
    /// remove the wrapped copy. Throws `rotationPending` while a rotation is unfinished
    /// (its previous key would be lost).
    @discardableResult
    func unwrapToPlain(password: String) throws -> SymmetricKey {
        let keys = try unwrapKeys(password: password)
        guard keys.previous == nil else { throw VaultError.rotationPending }
        try storePlain(verified: keys.current)
        return keys.current
    }

    /// Turn App Lock off with a key the caller just unwrapped with the password: store it
    /// bare, check it reads back, then remove the wrapped copy. Refuses while a rotation
    /// is unfinished.
    func storePlain(verified key: SymmetricKey) throws {
        guard try !hasPendingRotation() else { throw VaultError.rotationPending }
        guard store.write(Self.plainAccount, Self.base64(key)),
              let check = try plainKey(), Self.base64(check) == Self.base64(key) else {
            throw VaultError.storeFailed
        }
        store.delete(Self.wrappedAccount)
    }

    /// Whether the wrapped item holds two keys (a rotation not finished yet). Known from
    /// its length, without the password.
    func hasPendingRotation() throws -> Bool {
        guard let blob = try readItem(Self.wrappedAccount), let data = Data(base64Encoded: blob) else { return false }
        return data.count == Self.wrappedLength(keyCount: 2)
    }

    private static func wrappedLength(keyCount: Int) -> Int { 25 + 12 + 32 * keyCount + 16 }

    /// The App Lock password hash an older build kept (its lock: bare key + this hash),
    /// or nil if there is none. Throws when it can't be read: only "no such item" means
    /// no lock, so a Keychain error never opens the journal without the password.
    func legacyPasswordHash() throws -> String? {
        try readItem(Self.legacyHashAccount)
    }

    /// The key is wrapped now (or the lock is off): the older build's hash is not needed.
    func removeLegacyPasswordHash() {
        store.delete(Self.legacyHashAccount)
    }

    /// Delete both forms of the key ("Erase all local data").
    func deleteKeys() {
        store.delete(Self.plainAccount)
        store.delete(Self.wrappedAccount)
    }

    /// Remove a bare key left next to a wrapped one (an interrupted rotation: the wrapped
    /// item already holds that key as `previous`, or as the current key).
    func removePlainCopyIfWrapped() {
        if (try? readItem(Self.wrappedAccount)) != nil {
            store.delete(Self.plainAccount)
        }
    }

    /// Write the wrapped item in place and check it reads back byte for byte. Throws
    /// `unconfirmed` when the write was accepted but the read-back failed.
    private func writeWrapped(keys: [SymmetricKey], password: String) throws {
        let blob = try Self.seal(keys: keys, password: password, iterations: iterations)
        guard store.write(Self.wrappedAccount, blob) else { throw VaultError.storeFailed }
        let stored: String?
        do {
            stored = try readItem(Self.wrappedAccount)
        } catch {
            throw VaultError.unconfirmed
        }
        guard stored == blob else { throw VaultError.storeFailed }
    }

    // MARK: - Format

    /// Wrapped keys: base64( "DJXW" | version | iterations (UInt32 BE) | salt (16) |
    /// AES-GCM(nonce | 32 or 64 key bytes | tag) ). The header is authenticated as AAD.
    static func seal(_ key: SymmetricKey, password: String, iterations: UInt32) throws -> String {
        try seal(keys: [key], password: password, iterations: iterations)
    }

    static func seal(keys: [SymmetricKey], password: String, iterations: UInt32) throws -> String {
        guard (1...2).contains(keys.count) else { throw VaultError.corrupt }
        let salt = KeyDerivation.generateSalt()
        var header = magic
        header.append(formatVersion)
        withUnsafeBytes(of: iterations.bigEndian) { header.append(contentsOf: $0) }
        header.append(salt)
        let kek = try deriveKEK(password: password, salt: salt, iterations: iterations)
        let payload = keys.reduce(Data()) { $0 + $1.withUnsafeBytes { Data($0) } }
        let sealed = try AES.GCM.seal(payload, using: kek, authenticating: header)
        guard let combined = sealed.combined else { throw VaultError.corrupt }
        return (header + combined).base64EncodedString()
    }

    static func open(_ blob: String, password: String) throws -> [SymmetricKey] {
        guard let data = Data(base64Encoded: blob),
              data.count == wrappedLength(keyCount: 1) || data.count == wrappedLength(keyCount: 2) else {
            throw VaultError.corrupt
        }
        let bytes = [UInt8](data)
        guard Data(bytes[0..<4]) == magic, bytes[4] == formatVersion else { throw VaultError.corrupt }
        let iterations = bytes[5..<9].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard iterationRange.contains(iterations) else { throw VaultError.corrupt }
        let header = Data(bytes[0..<25])
        let salt = Data(bytes[9..<25])
        let kek = try deriveKEK(password: password, salt: salt, iterations: iterations)
        let raw: Data
        do {
            let box = try AES.GCM.SealedBox(combined: Data(bytes[25...]))
            raw = try AES.GCM.open(box, using: kek, authenticating: header)
        } catch {
            throw VaultError.wrongPassword
        }
        guard raw.count == 32 || raw.count == 64 else { throw VaultError.corrupt }
        return stride(from: 0, to: raw.count, by: 32).map { SymmetricKey(data: raw[raw.startIndex + $0 ..< raw.startIndex + $0 + 32]) }
    }

    /// Iteration count stored in a wrapped blob (for tests and diagnostics).
    static func iterations(of blob: String) -> UInt32? {
        guard let data = Data(base64Encoded: blob), data.count > 9 else { return nil }
        return [UInt8](data)[5..<9].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    private static func deriveKEK(password: String, salt: Data, iterations: UInt32) throws -> SymmetricKey {
        guard let derived = KeyDerivation.deriveKey(password: password, salt: salt, iterations: iterations) else {
            throw VaultError.wrongPassword
        }
        return SymmetricKey(data: derived)
    }

    private static func base64(_ key: SymmetricKey) -> String {
        key.withUnsafeBytes { Data($0) }.base64EncodedString()
    }

    /// nil when the item does not exist; throws when it exists but can't be read.
    private func readItem(_ account: String) throws -> String? {
        let (value, status) = store.read(account)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let value else { throw VaultError.unreadable(status) }
        return value
    }
}

/// App Lock state, derived from the key vault (plus the hash a pre-wrapping build kept).
enum AppLock {
    /// True when the app must ask for the password before opening the journal.
    /// An unreadable Keychain counts as locked (fail closed).
    static func isEnabled(vault: DatabaseKeyVault = DatabaseKeyVault()) -> Bool {
        do {
            return try vault.legacyPasswordHash() != nil || vault.state() == .wrapped
        } catch {
            return true
        }
    }
}
