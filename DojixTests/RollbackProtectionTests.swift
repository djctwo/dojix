import CryptoKit
import GRDB
import XCTest
@testable import Dojix

/// Rollback protection: every save has a generation, kept in the sealed file's header and
/// in the Keychain (here an in-memory stand-in). An older copy of the journal put back on
/// disk is not opened silently. All trades are fictional.
final class RollbackProtectionTests: XCTestCase {
    private var dir: URL!
    private var dbPath: String { dir.appendingPathComponent("Dojix.sqlite").path }
    private let key = SymmetricKey(size: .bits256)
    private let keychain = MemorySecretStore()
    private var generations: SaveGenerationStore { SaveGenerationStore(store: keychain) }
    private let fixedNow = Date(timeIntervalSince1970: 1_767_225_600)

    override func setUpWithError() throws {
        dir = try SecFixture.scratchDirectory()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func journal(store: SaveGenerationStore? = nil) throws -> DatabaseManager {
        let now = fixedNow
        return try DatabaseManager(path: dbPath, generationStore: store ?? generations, now: { now })
    }

    private func add(_ tickets: ClosedRange<Int64>, to db: DatabaseManager) throws {
        _ = try TradeRepository(database: db).bulkInsert(tickets.map { SecFixture.trade(ticket: $0) })
        db.flush()
    }

    private func tickets(_ db: DatabaseManager) throws -> [Int64] {
        try TradeRepository(database: db).fetchAll().map(\.ticket).sorted()
    }

    private func fileBytes() throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: dbPath))
    }

    /// A journal saved a few times, an older copy of its file, and the newer state.
    private func journalWithOlderCopy() throws -> (older: Data, olderGeneration: UInt64, newerGeneration: UInt64) {
        let db = try journal()
        try db.load(key: key)
        try add(1...2, to: db)
        let older = try fileBytes()
        let olderGeneration = db.savedGeneration
        try add(3...4, to: db)
        try db.unload()
        return (older, olderGeneration, db.savedGeneration)
    }

    // MARK: - Every save is counted

    func testEverySaveRaisesTheGenerationInTheFileAndTheKeychain() throws {
        let db = try journal()
        try db.load(key: key)
        let afterLoad = db.savedGeneration
        XCTAssertEqual(afterLoad, 1, "a new journal's first save is generation 1")
        try add(1...1, to: db)
        try add(2...2, to: db)
        XCTAssertGreaterThan(db.savedGeneration, afterLoad)

        let stamp = try XCTUnwrap(DatabaseEncryption.openJournal(fileBytes(), key: key).stamp)
        XCTAssertEqual(stamp.generation, db.savedGeneration)
        XCTAssertEqual(stamp.savedAt, fixedNow)
        XCTAssertEqual(stamp.epoch.count, 16)
        let record = try XCTUnwrap(generations.lastSaved())
        XCTAssertEqual(record.stamp, stamp)
        XCTAssertTrue(record.matches(try fileBytes()), "the record holds the hash of the file written")
    }

    // MARK: - Older copy

    func testOlderCopyOfTheJournalIsNotOpenedSilently() throws {
        let state = try journalWithOlderCopy()
        try state.older.write(to: URL(fileURLWithPath: dbPath))

        let launch = try journal()
        XCTAssertThrowsError(try launch.load(key: key)) { error in
            guard let older = error as? OlderJournalError else { return XCTFail("expected OlderJournalError, got \(error)") }
            XCTAssertEqual(older.fileStamp?.generation, state.olderGeneration)
            XCTAssertEqual(older.lastSaved.generation, state.newerGeneration)
            XCTAssertTrue(older.localizedDescription.hasPrefix("This journal is older than the last one this Mac saved (saved "))
        }
        XCTAssertFalse(launch.isLoaded, "nothing is opened")
        XCTAssertEqual(try fileBytes(), state.older, "nothing is written")
        XCTAssertEqual(generations.lastSaved()?.stamp.generation, state.newerGeneration, "the record is kept")
    }

    func testOpeningAnOlderJournalAnywayStartsANewEpoch() throws {
        let state = try journalWithOlderCopy()
        try state.older.write(to: URL(fileURLWithPath: dbPath))
        let oldEpoch = try XCTUnwrap(generations.lastSaved()?.stamp.epoch)

        let confirmed = try journal()
        try confirmed.load(key: key, allowOlderJournal: true)
        XCTAssertEqual(try tickets(confirmed), [1, 2], "the older copy is what opens")
        // The count goes on from the newer save (never down), in a new epoch
        XCTAssertEqual(confirmed.savedGeneration, state.newerGeneration + 1)
        let record = try XCTUnwrap(generations.lastSaved())
        XCTAssertEqual(record.stamp.generation, state.newerGeneration + 1)
        XCTAssertNotEqual(record.stamp.epoch, oldEpoch)
        try confirmed.unload()

        // From now on it is the current journal: no further warning
        let next = try journal()
        XCTAssertNoThrow(try next.load(key: key))
    }

    /// The user confirms opening an older copy; the saves made after that copy form an
    /// abandoned branch. Returns an abandoned file with the same generation as the
    /// confirmed branch's last save, and one with a higher generation.
    private func abandonedBranch() throws -> (sameGeneration: Data, abandonedNewer: Data) {
        let db = try journal()
        try db.load(key: key)                       // save 1
        try add(1...2, to: db)                      // 2
        let older = try fileBytes()
        try add(3...3, to: db)                      // 3
        try add(4...4, to: db)                      // 4
        try add(5...5, to: db)                      // 5
        let sameGeneration = try fileBytes()
        try add(6...6, to: db)                      // 6
        let abandonedNewer = try fileBytes()
        try db.unload()                             // 7

        try older.write(to: URL(fileURLWithPath: dbPath))
        let confirmed = try journal()
        try confirmed.load(key: key, allowOlderJournal: true)
        try add(10...10, to: confirmed)
        try confirmed.unload()
        // Opened at 2: whatever the counter does now, the confirmed branch ended up at a
        // generation at or past 5 and its file is the current one.
        XCTAssertGreaterThanOrEqual(confirmed.savedGeneration, 5)
        return (sameGeneration, abandonedNewer)
    }

    func testReplayingTheAbandonedBranchsNewerFileIsCaught() throws {
        let branch = try abandonedBranch()
        try branch.abandonedNewer.write(to: URL(fileURLWithPath: dbPath))
        XCTAssertThrowsError(try journal().load(key: key)) { error in
            XCTAssertTrue(error is OlderJournalError, "got \(error)")
        }
    }

    func testFileWithTheSameGenerationFromTheAbandonedBranchIsCaught() throws {
        let branch = try abandonedBranch()
        try branch.sameGeneration.write(to: URL(fileURLWithPath: dbPath))
        XCTAssertThrowsError(try journal().load(key: key)) { error in
            XCTAssertTrue(error is OlderJournalError, "got \(error)")
        }
    }

    func testConfirmingAnOlderJournalNeverLowersTheCounter() throws {
        let state = try journalWithOlderCopy()
        try state.older.write(to: URL(fileURLWithPath: dbPath))
        let confirmed = try journal()
        try confirmed.load(key: key, allowOlderJournal: true)
        XCTAssertGreaterThan(confirmed.savedGeneration, state.newerGeneration)
        XCTAssertEqual(generations.lastSaved()?.stamp.generation, confirmed.savedGeneration)
    }

    func testNewerJournalThanTheRecordIsAcceptedAndTheRecordUpdated() throws {
        let state = try journalWithOlderCopy()
        // The record lags behind in the same epoch (a Keychain write failed)
        let epoch = try XCTUnwrap(DatabaseEncryption.openJournal(fileBytes(), key: key).stamp?.epoch)
        generations.record(SaveRecord(stamp: JournalStamp(epoch: epoch, generation: 1, savedAt: fixedNow),
                                      sealedFile: Data("an earlier file".utf8)))

        let launch = try journal()
        XCTAssertNoThrow(try launch.load(key: key))
        XCTAssertEqual(launch.savedGeneration, state.newerGeneration + 1)
        XCTAssertEqual(generations.lastSaved()?.stamp.generation, state.newerGeneration + 1)

        // Record lost altogether: also accepted
        generations.delete()
        try launch.unload()
        let again = try journal()
        XCTAssertNoThrow(try again.load(key: key))
        XCTAssertEqual(generations.lastSaved()?.stamp.generation, again.savedGeneration)
    }

    func testChangedGenerationInTheHeaderDoesNotOpen() throws {
        let state = try journalWithOlderCopy()
        var bytes = [UInt8](try fileBytes())
        bytes[28] ^= 0x01 // generation is authenticated (AES-GCM associated data)
        try Data(bytes).write(to: URL(fileURLWithPath: dbPath))

        let launch = try journal()
        XCTAssertThrowsError(try launch.load(key: key)) { error in
            XCTAssertEqual(error as? DatabaseEncryption.EncryptionError, .decryptionFailed)
        }
        XCTAssertFalse(launch.isLoaded)
        XCTAssertEqual(generations.lastSaved()?.stamp.generation, state.newerGeneration)
    }

    // MARK: - Migration

    func testJournalFromBeforeGenerationsOpensAsGenerationZero() throws {
        // A journal sealed by an earlier build: the bare AES-GCM box, no header
        let source = try DatabaseManager(inMemory: true)
        _ = try TradeRepository(database: source).bulkInsert([SecFixture.trade(ticket: 7)])
        let image = try source.dbQueue.writeWithoutTransaction { db in try DatabaseManager.serialize(db) }
        try DatabaseEncryption.writeSealed(image, key: key, to: dbPath)
        XCTAssertNil(try DatabaseEncryption.openJournal(fileBytes(), key: key).stamp)

        let db = try journal()
        try db.load(key: key)
        XCTAssertEqual(try tickets(db), [7])
        XCTAssertEqual(db.savedGeneration, 1, "counting starts")
        XCTAssertEqual(try DatabaseEncryption.openJournal(fileBytes(), key: key).stamp?.generation, 1)
        XCTAssertEqual(generations.lastSaved()?.stamp.generation, 1)
    }

    func testSameGenerationButADifferentFileIsCaught() throws {
        let db = try journal()
        try db.load(key: key)
        try add(1...2, to: db)
        try db.unload()
        let record = try XCTUnwrap(generations.lastSaved())

        // Another file claiming exactly the recorded save (same epoch and generation)
        let other = try DatabaseManager(inMemory: true)
        _ = try TradeRepository(database: other).bulkInsert([SecFixture.trade(ticket: 99)])
        let image = try other.dbQueue.writeWithoutTransaction { db in try DatabaseManager.serialize(db) }
        try DatabaseEncryption.writeJournal(image, key: key, stamp: record.stamp, to: dbPath)

        XCTAssertThrowsError(try journal().load(key: key)) { error in
            XCTAssertTrue(error is OlderJournalError, "got \(error)")
        }
    }

    func testPreGenerationFileAfterGenerationsWereRecordedIsAnOlderJournal() throws {
        let recorded = JournalStamp(epoch: JournalStamp.newEpoch(), generation: 9, savedAt: fixedNow)
        generations.record(SaveRecord(stamp: recorded, sealedFile: Data()))
        let source = try DatabaseManager(inMemory: true)
        let image = try source.dbQueue.writeWithoutTransaction { db in try DatabaseManager.serialize(db) }
        try DatabaseEncryption.writeSealed(image, key: key, to: dbPath)

        XCTAssertThrowsError(try journal().load(key: key)) { error in
            XCTAssertEqual(error as? OlderJournalError,
                           OlderJournalError(fileStamp: nil, lastSaved: recorded))
        }
        // A plaintext journal (older build) put back is treated the same way
        try FileManager.default.removeItem(atPath: dbPath)
        try SecFixture.writeLegacyPlaintextJournal(at: dbPath, trades: [SecFixture.trade(ticket: 1)])
        XCTAssertThrowsError(try journal().load(key: key)) { error in
            XCTAssertTrue(error is OlderJournalError)
        }
    }

    func testMissingJournalFileContinuesTheCount() throws {
        generations.record(SaveRecord(stamp: JournalStamp(epoch: JournalStamp.newEpoch(), generation: 41, savedAt: fixedNow),
                                      sealedFile: Data()))
        let db = try journal()
        XCTAssertNoThrow(try db.load(key: key))
        XCTAssertEqual(db.savedGeneration, 42)
    }

    // MARK: - Keychain failure, restore

    private final class RefusingStore: SecretStore, @unchecked Sendable {
        func read(_ account: String) -> (value: String?, status: OSStatus) { (nil, errSecItemNotFound) }
        func write(_ account: String, _ value: String) -> Bool { false }
        func delete(_ account: String) {}
    }

    func testKeychainThatRefusesTheRecordLosesNoData() throws {
        let refusing = SaveGenerationStore(store: RefusingStore())
        let db = try journal(store: refusing)
        try db.load(key: key)
        try add(1...3, to: db)
        XCTAssertNil(db.lastSaveError, "saving goes on")
        XCTAssertGreaterThan(db.savedGeneration, 1)
        try db.unload()

        let reopened = try journal(store: refusing)
        try reopened.load(key: key)
        XCTAssertEqual(try tickets(reopened), [1, 2, 3])
    }

    func testRestoringABackupRaisesNoFalseAlarm() throws {
        let db = try journal()
        try db.load(key: key)
        try add(1...5, to: db)

        let source = try DatabaseManager(inMemory: true)
        _ = try TradeRepository(database: source).bulkInsert([SecFixture.trade(ticket: 100)])
        let backup = dir.appendingPathComponent("backup.dojix")
        try BackupService.writeBackup(of: source, to: backup)
        let before = db.savedGeneration
        _ = try BackupService.restore(from: backup, into: db)
        XCTAssertGreaterThan(db.savedGeneration, before, "a restore is a newer save")
        try db.unload()

        let launch = try journal()
        XCTAssertNoThrow(try launch.load(key: key))
        XCTAssertEqual(try tickets(launch), [100])
    }

    func testStoredRecordFormat() throws {
        let epoch = Data((0..<16).map { UInt8($0) })
        let stamp = JournalStamp(epoch: epoch, generation: 12, savedAt: Date(timeIntervalSince1970: 1_700_000_000.7))
        let record = SaveRecord(stamp: stamp, sealedFile: Data("file".utf8))
        let encoded = SaveGenerationStore.encode(record)
        XCTAssertTrue(encoded.hasPrefix("v2:000102030405060708090a0b0c0d0e0f:12:1700000000:"))
        XCTAssertEqual(SaveGenerationStore.decode(encoded), record)
        let hash = record.fileHash.hexString
        for damaged in ["", "v1:12:1700000000", "v2:00:12:1:\(hash)", "v2:\(epoch.hexString):-1:5:\(hash)",
                        "v2:\(epoch.hexString):1:5:abc", "v2:+f\(epoch.hexString.dropFirst(2)):1:5:\(hash)",
                        "v2:\(epoch.hexString):1:5"] {
            XCTAssertNil(SaveGenerationStore.decode(damaged), damaged)
        }
        keychain.write(SaveGenerationStore.account, "garbage")
        XCTAssertNil(generations.lastSaved(), "a damaged record is ignored")
    }
}
