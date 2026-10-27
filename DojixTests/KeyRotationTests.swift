import AppKit
import CryptoKit
import XCTest
@testable import Dojix

/// Turning App Lock on (or changing its password) rotates the database key, so an old
/// bare key from a Keychain or disk backup decrypts nothing. Every interruption point
/// must leave the journal decryptable with the password.
final class KeyRotationTests: XCTestCase {
    private let fast: UInt32 = 1_000
    private let password = "fictional-lock-pw"
    private var dir: URL!
    private var store: MemorySecretStore!
    private var vault: DatabaseKeyVault!

    override func setUpWithError() throws {
        dir = try SecFixture.scratchDirectory()
        store = MemorySecretStore()
        vault = DatabaseKeyVault(store: store, iterations: fast)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private var dbPath: String { dir.appendingPathComponent("Dojix.sqlite").path }
    private var journalBytes: Data { (try? Data(contentsOf: URL(fileURLWithPath: dbPath))) ?? Data() }
    private func raw(_ key: SymmetricKey) -> Data { key.withUnsafeBytes { Data($0) } }

    /// App Lock off: a journal with two trades and one screenshot, sealed with the bare key.
    private func makeUnlockedJournal() throws -> (DatabaseManager, ScreenshotManager, String, SymmetricKey) {
        let key = try vault.createPlainKey()
        let db = try DatabaseManager(path: dbPath)
        try db.load(key: key)
        try TradeRepository(database: db).bulkInsert([SecFixture.trade(ticket: 1), SecFixture.trade(ticket: 2)])
        try db.saveNow()
        let shots = ScreenshotManager(baseDir: dir.appendingPathComponent("Screenshots"), keyProvider: { [db] in db.currentKey })
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus(); NSColor.blue.setFill(); NSRect(x: 0, y: 0, width: 2, height: 2).fill(); image.unlockFocus()
        let name = try shots.saveImage(image, for: 1)
        return (db, shots, name, key)
    }

    /// What a relaunch + unlock does: unwrap, load (with the previous key as fallback),
    /// finish the rotation. Returns the reopened journal.
    private func relaunchAndUnlock(password: String) throws -> DatabaseManager {
        let keys = try AppState.unlockKeys(vault: vault, password: password, legacyHash: nil)
        let db = try DatabaseManager(path: dbPath)
        try db.load(key: keys.current, previousKey: keys.previous)
        let shots = ScreenshotManager(baseDir: dir.appendingPathComponent("Screenshots"), keyProvider: { [db] in db.currentKey })
        try KeyRotation.finishAfterUnlock(keys: keys, password: password, vault: vault, database: db, screenshots: shots)
        return db
    }

    private func assertOnlyOpensWith(_ key: SymmetricKey, notWith old: SymmetricKey, screenshot name: String,
                                     file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertNoThrow(try DatabaseEncryption.open(journalBytes, key: key), file: file, line: line)
        XCTAssertThrowsError(try DatabaseEncryption.open(journalBytes, key: old), "old key still opens the journal",
                             file: file, line: line)
        let shotPath = dir.appendingPathComponent("Screenshots/1/\(name)")
        let sealed = try Data(contentsOf: shotPath).dropFirst(4)
        XCTAssertNoThrow(try DatabaseEncryption.open(sealed, key: key), file: file, line: line)
        XCTAssertThrowsError(try DatabaseEncryption.open(sealed, key: old), "old key still opens a screenshot",
                             file: file, line: line)
    }

    func testEnablingLockRotatesKeyAndOldKeyOpensNothing() throws {
        let (db, shots, name, oldKey) = try makeUnlockedJournal()

        try KeyRotation.rotate(vault: vault, database: db, screenshots: shots, oldKey: oldKey, password: password)

        XCTAssertNil(store.value(DatabaseKeyVault.plainAccount), "no bare key left")
        let keys = try vault.unwrapKeys(password: password)
        XCTAssertNil(keys.previous)
        XCTAssertNotEqual(raw(keys.current), raw(oldKey))
        try assertOnlyOpensWith(keys.current, notWith: oldKey, screenshot: name)
        XCTAssertEqual(try TradeRepository(database: try relaunchAndUnlock(password: password)).count(), 2)
    }

    func testInterruptedAfterNewKeyStoredBeforeJournalResealed() throws {
        let (db, _, name, oldKey) = try makeUnlockedJournal()
        // Step 1 done, then the app dies: journal + screenshot still sealed with the old key
        _ = try vault.beginRotation(from: oldKey, password: password)
        XCTAssertNil(store.value(DatabaseKeyVault.plainAccount))
        _ = db

        let reopened = try relaunchAndUnlock(password: password)
        XCTAssertEqual(try TradeRepository(database: reopened).count(), 2, "the journal is still decryptable")
        let keys = try vault.unwrapKeys(password: password)
        XCTAssertNil(keys.previous, "the rotation was completed at unlock")
        try assertOnlyOpensWith(keys.current, notWith: oldKey, screenshot: name)
    }

    func testInterruptedAfterJournalResealedBeforeScreenshots() throws {
        let (db, _, name, oldKey) = try makeUnlockedJournal()
        let newKey = try vault.beginRotation(from: oldKey, password: password)
        try db.rekey(to: newKey) // journal re-sealed; screenshots not yet; then the app dies
        XCTAssertNoThrow(try DatabaseEncryption.open(journalBytes, key: newKey))

        let reopened = try relaunchAndUnlock(password: password)
        XCTAssertEqual(try TradeRepository(database: reopened).count(), 2)
        try assertOnlyOpensWith(newKey, notWith: oldKey, screenshot: name)
        XCTAssertNil(try vault.unwrapKeys(password: password).previous)
    }

    func testInterruptedBeforeAnythingWasStored() throws {
        let (_, _, _, oldKey) = try makeUnlockedJournal()
        // The app died before step 1: still App Lock off, bare key, journal opens with it
        XCTAssertEqual(try vault.state(), .plain)
        let db = try DatabaseManager(path: dbPath)
        try db.load(key: try XCTUnwrap(try vault.plainKey()))
        XCTAssertEqual(try TradeRepository(database: db).count(), 2)
        XCTAssertEqual(raw(try XCTUnwrap(try vault.plainKey())), raw(oldKey))
    }

    func testChangingPasswordRotatesAgain() throws {
        let (db, shots, name, firstKey) = try makeUnlockedJournal()
        try KeyRotation.rotate(vault: vault, database: db, screenshots: shots, oldKey: firstKey, password: password)
        let secondKey = try vault.unwrap(password: password)

        // Change password: unwrap with the current password, rotate under the new one
        try KeyRotation.rotate(vault: vault, database: db, screenshots: shots,
                               oldKey: try vault.unwrap(password: password), password: "new-fictional-pw")

        XCTAssertThrowsError(try vault.unwrap(password: password), "the old password no longer works")
        let thirdKey = try vault.unwrap(password: "new-fictional-pw")
        XCTAssertNotEqual(raw(thirdKey), raw(secondKey))
        try assertOnlyOpensWith(thirdKey, notWith: secondKey, screenshot: name)
        XCTAssertEqual(try TradeRepository(database: try relaunchAndUnlock(password: "new-fictional-pw")).count(), 2)
    }
}
