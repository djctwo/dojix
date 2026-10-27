import CryptoKit
import XCTest
@testable import Dojix

/// A key rotation may drop the old key only once nothing on disk needs it any more, and
/// once the new key is stored the change counts as made (the new password is in force).
final class KeyRotationSafetyTests: XCTestCase {
    private let fast: UInt32 = 1_000
    private let password = "fictional-lock-pw"
    private var dir: URL!
    private var store: MemorySecretStore!
    private var vault: DatabaseKeyVault!
    private var immutable: [URL] = []

    override func setUpWithError() throws {
        dir = try SecFixture.scratchDirectory()
        store = MemorySecretStore()
        vault = DatabaseKeyVault(store: store, iterations: fast)
    }

    override func tearDownWithError() throws {
        immutable.forEach { RaceFixture.setImmutable($0, false) }
        try? FileManager.default.removeItem(at: dir)
    }

    private var dbPath: String { dir.appendingPathComponent("Dojix.sqlite").path }
    private var shotsDir: URL { dir.appendingPathComponent("Screenshots") }
    private func raw(_ key: SymmetricKey) -> Data { key.withUnsafeBytes { Data($0) } }

    private func lockFile(_ url: URL) {
        RaceFixture.setImmutable(url, true)
        immutable.append(url)
    }

    /// App Lock off: two trades and one screenshot, sealed with the bare key.
    private func makeJournal(hooks: DatabaseManager.Hooks = .init()) throws
        -> (DatabaseManager, ScreenshotManager, URL, SymmetricKey) {
        let key = try vault.createPlainKey()
        let db = try DatabaseManager(path: dbPath, hooks: hooks)
        try db.load(key: key)
        try TradeRepository(database: db).bulkInsert([SecFixture.trade(ticket: 1), SecFixture.trade(ticket: 2)])
        try db.saveNow()
        let shots = ScreenshotManager(baseDir: shotsDir, keyProvider: { [db] in db.currentKey })
        let name = try RaceFixture.saveScreenshot(shots)
        return (db, shots, shotsDir.appendingPathComponent("1/\(name)"), key)
    }

    /// What a relaunch + unlock does (see `KeyRotationTests`).
    private func relaunchAndUnlock(password: String) throws -> DatabaseManager {
        let keys = try AppState.unlockKeys(vault: vault, password: password, legacyHash: nil)
        let db = try DatabaseManager(path: dbPath)
        try db.load(key: keys.current, previousKey: keys.previous)
        let shots = ScreenshotManager(baseDir: shotsDir, keyProvider: { [db] in db.currentKey })
        try KeyRotation.finishAfterUnlock(keys: keys, password: password, vault: vault, database: db, screenshots: shots)
        return db
    }

    // MARK: - Finding 1: never drop the old key while the journal doesn't open with the new one

    func testOldKeyIsKeptWhenTheJournalOnDiskDoesNotOpenWithTheNewKey() throws {
        let (db, shots, _, oldKey) = try makeJournal()
        // Another writer puts back a journal sealed with the old key right before step 3.
        let stale = try Data(contentsOf: URL(fileURLWithPath: dbPath))
        let path = dbPath
        let outcome = try KeyRotation.rotate(vault: vault, database: db, screenshots: shots, oldKey: oldKey,
                                             password: password, beforeFinishing: {
            try? DatabaseEncryption.writeAtomically(stale, to: path)
        })
        XCTAssertEqual(outcome, .finishesOnNextUnlock)
        let keys = try vault.unwrapKeys(password: password)
        XCTAssertEqual(keys.previous.map(raw), raw(oldKey), "the only key that opens the journal must stay stored")
        XCTAssertEqual(try TradeRepository(database: try relaunchAndUnlock(password: password)).count(), 2)
    }

    // MARK: - Finding 2: files that could not be re-sealed keep the old key

    func testAScreenshotThatCannotBeResealedKeepsTheOldKey() throws {
        let (db, shots, shot, oldKey) = try makeJournal()
        lockFile(shot)

        let outcome = try KeyRotation.rotate(vault: vault, database: db, screenshots: shots, oldKey: oldKey, password: password)

        XCTAssertEqual(outcome, .finishesOnNextUnlock)
        XCTAssertEqual(try vault.unwrapKeys(password: password).previous.map(raw), raw(oldKey))
        XCTAssertTrue(RaceFixture.screenshot(at: shot, opensWith: oldKey))
        // Once the file can be written again, the next unlock finishes the rotation.
        RaceFixture.setImmutable(shot, false)
        _ = try relaunchAndUnlock(password: password)
        let keys = try vault.unwrapKeys(password: password)
        XCTAssertNil(keys.previous)
        XCTAssertTrue(RaceFixture.screenshot(at: shot, opensWith: keys.current))
    }

    func testAJournalCopyThatCannotBeResealedKeepsTheOldKey() throws {
        let (db, shots, _, oldKey) = try makeJournal()
        let copy = dir.appendingPathComponent("Dojix.sqlite.unreadable-1")
        try DatabaseEncryption.writeSealed(try RaceFixture.journalImage(trades: 1), key: oldKey, to: copy.path)
        lockFile(copy)

        XCTAssertEqual(DatabaseEncryption.resealStrayCopies(besides: dbPath, from: oldKey, to: SymmetricKey(size: .bits256)),
                       [copy])
        let outcome = try KeyRotation.rotate(vault: vault, database: db, screenshots: shots, oldKey: oldKey, password: password)
        XCTAssertEqual(outcome, .finishesOnNextUnlock)
        XCTAssertEqual(try vault.unwrapKeys(password: password).previous.map(raw), raw(oldKey))
    }

    func testANewRotationOrDisablingNeverDropsAPendingPreviousKey() throws {
        let oldKey = try vault.createPlainKey()
        let current = try vault.beginRotation(from: oldKey, password: password) // [current, old] pending
        XCTAssertThrowsError(try vault.beginRotation(from: current, password: "another-fictional-pw")) {
            XCTAssertEqual($0 as? DatabaseKeyVault.VaultError, .rotationPending)
        }
        XCTAssertThrowsError(try vault.unwrapToPlain(password: password)) {
            XCTAssertEqual($0 as? DatabaseKeyVault.VaultError, .rotationPending)
        }
        let keys = try vault.unwrapKeys(password: password)
        XCTAssertEqual(keys.previous.map(raw), raw(oldKey), "nothing was dropped")
    }

    func testLegacyScreenshotIsSealedWithTheKeyInForceWhenItIsWritten() throws {
        let key = Shared(SymmetricKey(size: .bits256))
        let rotated = SymmetricKey(size: .bits256)
        let shots = ScreenshotManager(baseDir: shotsDir, keyProvider: { key.value },
                                      willSealLegacyFile: { key.value = rotated })
        let folder = shotsDir.appendingPathComponent("1")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("\(UUID().uuidString).jpg")
        try Data("fictional jpeg bytes".utf8).write(to: file)

        XCTAssertEqual(shots.encryptLegacyFiles(), 1)
        XCTAssertTrue(RaceFixture.screenshot(at: file, opensWith: rotated),
                      "a file sealed with a key captured before a rotation is lost when the old key is dropped")
    }

    // MARK: - Finding 3: once the new key is stored, the change is made

    func testAFailedJournalSaveAfterTheNewKeyIsStoredStillCountsAsChanged() throws {
        let failing = Shared(false)
        let hooks = DatabaseManager.Hooks(willPersist: { if failing.value { throw POSIXError(.ENOSPC) } })
        let (db, shots, _, oldKey) = try makeJournal(hooks: hooks)
        failing.value = true

        var outcome: KeyRotation.Outcome?
        XCTAssertNoThrow(outcome = try KeyRotation.rotate(vault: vault, database: db, screenshots: shots,
                                                          oldKey: oldKey, password: password),
                         "the new password is already in force: reporting failure would lock the user out")
        XCTAssertEqual(outcome, .finishesOnNextUnlock)
        XCTAssertNoThrow(try vault.unwrapKeys(password: password))
        failing.value = false
        try db.unload()
        let reopened = try relaunchAndUnlock(password: password)
        XCTAssertEqual(try TradeRepository(database: reopened).count(), 2)
        XCTAssertNil(try vault.unwrapKeys(password: password).previous)
    }

    func testRotatingAClosedJournalCountsAsChangedAndOpensWithTheNewPassword() throws {
        let (db, shots, _, oldKey) = try makeJournal()
        try db.unload()   // a lock got in first
        let outcome = try KeyRotation.rotate(vault: vault, database: db, screenshots: shots, oldKey: oldKey, password: password)
        XCTAssertEqual(outcome, .finishesOnNextUnlock)
        XCTAssertEqual(try TradeRepository(database: try relaunchAndUnlock(password: password)).count(), 2)
    }
}
