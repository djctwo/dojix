import CryptoKit
import GRDB
import XCTest
@testable import Dojix

/// No plaintext journal on disk (F1–F4): the database lives in memory and only an
/// encrypted file is written; plaintext left by older builds is encrypted at once.
final class EncryptedJournalTests: XCTestCase {
    private var dir: URL!
    private var dbPath: String { dir.appendingPathComponent("Dojix.sqlite").path }

    override func setUpWithError() throws {
        dir = try SecFixture.scratchDirectory()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func count(_ db: DatabaseManager) throws -> Int {
        try TradeRepository(database: db).count()
    }

    func testNothingIsReadFromDiskBeforeTheKeyIsGiven() throws {
        let key = SymmetricKey(size: .bits256)
        let first = try DatabaseManager(path: dbPath)
        try first.load(key: key)
        try TradeRepository(database: first).bulkInsert([SecFixture.trade(ticket: 1)])
        try first.saveNow()

        // A fresh manager (an app launch) is empty and read-only until load(key:)
        let launch = try DatabaseManager(path: dbPath)
        XCTAssertFalse(launch.isLoaded)
        XCTAssertNil(launch.currentKey)
        XCTAssertThrowsError(try count(launch), "no journal tables before unlock")
        XCTAssertThrowsError(try launch.dbQueue.write { db in try db.execute(sql: "CREATE TABLE x(y)") })
        XCTAssertEqual(SecFixture.plaintextFiles(in: dir), [])
    }

    func testCommittedChangesAreSavedEncryptedOnly() throws {
        let key = SymmetricKey(size: .bits256)
        let db = try DatabaseManager(path: dbPath)
        try db.load(key: key)
        // A plain write (no explicit save) is persisted by the commit observer
        try TradeRepository(database: db).bulkInsert((1...20).map { SecFixture.trade(ticket: Int64($0)) })
        db.flush()

        XCTAssertEqual(SecFixture.plaintextFiles(in: dir), [], "no plaintext SQLite file or WAL on disk")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dbPath + "-wal"))
        let perms = try FileManager.default.attributesOfItem(atPath: dbPath)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600)

        let reopened = try DatabaseManager(path: dbPath)
        try reopened.load(key: key)
        XCTAssertEqual(try count(reopened), 20)

        let wrongKey = try DatabaseManager(path: dbPath)
        XCTAssertThrowsError(try wrongKey.load(key: SymmetricKey(size: .bits256)))
        XCTAssertFalse(wrongKey.isLoaded)
    }

    func testUncleanShutdownPlaintextIsEncryptedOnLoad() throws {
        // An older build crashed: plaintext Dojix.sqlite + a -wal holding the latest rows
        try SecFixture.writeLegacyPlaintextJournal(at: dbPath, trades: (1...5).map { SecFixture.trade(ticket: Int64($0)) })
        XCTAssertTrue(FileManager.default.fileExists(atPath: dbPath + "-wal"))
        XCTAssertFalse(SecFixture.plaintextFiles(in: dir).isEmpty)

        let key = SymmetricKey(size: .bits256)
        let db = try DatabaseManager(path: dbPath)
        try db.load(key: key)

        XCTAssertEqual(try count(db), 5, "rows still in the -wal are kept")
        XCTAssertEqual(SecFixture.plaintextFiles(in: dir), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: dbPath + "-wal"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dbPath + "-shm"))
    }

    func testPlaintextIsEncryptedBeforeUnlockWithoutLoading() throws {
        try SecFixture.writeLegacyPlaintextJournal(at: dbPath, trades: (1...3).map { SecFixture.trade(ticket: Int64($0)) })
        let key = SymmetricKey(size: .bits256)

        try DatabaseManager.encryptPlaintextFileInPlace(at: dbPath, key: key)

        XCTAssertEqual(SecFixture.plaintextFiles(in: dir), [])
        let db = try DatabaseManager(path: dbPath)
        try db.load(key: key)
        XCTAssertEqual(try count(db), 3)
    }

    func testStrayPlaintextCopiesAreEncryptedAndEraseDeletesThem() throws {
        // Copies older builds left: a pre-restore safety copy and a set-aside unreadable DB
        try SecFixture.writeLegacyPlaintextJournal(at: dbPath + ".pre-restore-backup", trades: [SecFixture.trade(ticket: 7)])
        try SecFixture.writeLegacyPlaintextJournal(at: dbPath + ".unreadable-1700000000", trades: [SecFixture.trade(ticket: 8)])
        XCTAssertFalse(SecFixture.plaintextFiles(in: dir).isEmpty)

        let key = SymmetricKey(size: .bits256)
        let db = try DatabaseManager(path: dbPath)
        try db.load(key: key)
        XCTAssertEqual(SecFixture.plaintextFiles(in: dir), [], "stray copies are sealed, not left readable")
        // Sealed, not destroyed: the copy still opens with the key
        let sealed = try Data(contentsOf: URL(fileURLWithPath: dbPath + ".pre-restore-backup"))
        XCTAssertTrue(DatabaseEncryption.isPlainSQLite(try DatabaseEncryption.open(sealed, key: key)))

        let shots = dir.appendingPathComponent("Screenshots")
        try FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
        try LocalDataEraser.eraseAll(database: db, screenshotsDirectory: shots)
        let left = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(left, [], "erase removes the journal and every copy next to it")
        XCTAssertFalse(db.isLoaded)
    }

    func testLockWipesMemoryAndUnlockRestores() throws {
        let key = SymmetricKey(size: .bits256)
        let db = try DatabaseManager(path: dbPath)
        try db.load(key: key)
        try TradeRepository(database: db).bulkInsert([SecFixture.trade(ticket: 1), SecFixture.trade(ticket: 2)])

        try db.unload()
        XCTAssertFalse(db.isLoaded)
        XCTAssertThrowsError(try count(db), "decrypted rows are gone from memory while locked")
        XCTAssertThrowsError(try TradeRepository(database: db).bulkInsert([SecFixture.trade(ticket: 3)]),
                             "writes while locked are refused, never silently lost")

        try db.load(key: key)
        XCTAssertEqual(try count(db), 2)
    }

    func testBackupExportIsAPlainSQLiteFileOwnerOnly() throws {
        let key = SymmetricKey(size: .bits256)
        let db = try DatabaseManager(path: dbPath)
        try db.load(key: key)
        try TradeRepository(database: db).bulkInsert([SecFixture.trade(ticket: 1)])

        let backup = dir.appendingPathComponent("export.dojix")
        try BackupService.writeBackup(of: db, to: backup)
        XCTAssertTrue(DatabaseEncryption.isPlainSQLite(try Data(contentsOf: backup)))
        let perms = try FileManager.default.attributesOfItem(atPath: backup.path)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600)
    }
}
