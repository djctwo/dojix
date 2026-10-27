import CryptoKit
import GRDB
import XCTest
@testable import Dojix

/// Races between a lock (`unload`) and a key change or restore, and a save that fails
/// while the journal is opened. Each race is forced with hooks: the lock's save is held
/// at `willPersist` while the other call reaches the database queue.
final class DatabaseRaceTests: XCTestCase {
    private var dir: URL!
    private let oldKey = SymmetricKey(size: .bits256)
    private let newKey = SymmetricKey(size: .bits256)

    override func setUpWithError() throws {
        dir = try SecFixture.scratchDirectory()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private var dbPath: String { dir.appendingPathComponent("Dojix.sqlite").path }
    private var journalFile: Data { (try? Data(contentsOf: URL(fileURLWithPath: dbPath))) ?? Data() }

    /// A journal with two trades sealed with `oldKey`, whose next save (once `hold` is
    /// armed) stops at `willPersist` until released.
    private func journalWithHeldSave() throws -> (DatabaseManager, armed: Shared<Bool>, reached: Signal,
                                                  release: Signal, waiting: Signal) {
        let armed = Shared(false), reached = Signal(), release = Signal(), waiting = Signal()
        let hooks = DatabaseManager.Hooks(
            willPersist: {
                guard armed.exchange(false) else { return }
                reached.fire()
                release.wait("release of the held save")
            },
            willWaitForDatabase: { waiting.fire() })
        let db = try DatabaseManager(path: dbPath, hooks: hooks)
        try db.load(key: oldKey)
        try TradeRepository(database: db).bulkInsert([SecFixture.trade(ticket: 1), SecFixture.trade(ticket: 2)])
        try db.saveNow()
        db.flush()
        return (db, armed, reached, release, waiting)
    }

    // MARK: - Finding 1: rekey vs lock

    func testRekeyRacingALockNeverReportsSuccessForAFileItDidNotSeal() throws {
        let (db, armed, reached, release, waiting) = try journalWithHeldSave()
        armed.value = true
        let lockDone = RaceFixture.inBackground { try? db.unload() }
        reached.wait("the lock's save")

        let rekeyError = Shared<Error?>(nil)
        let newKey = self.newKey
        let rekeyDone = RaceFixture.inBackground {
            do { try db.rekey(to: newKey) } catch { rekeyError.value = error }
        }
        waiting.wait("rekey reaching the database queue")
        release.fire()
        lockDone.wait("lock")
        rekeyDone.wait("rekey")

        if rekeyError.value == nil {
            XCTAssertNoThrow(try DatabaseEncryption.openJournal(journalFile, key: newKey),
                             "rekey reported success, but the journal on disk is not sealed with the new key")
        }
        XCTAssertNoThrow(try DatabaseEncryption.openJournal(journalFile, key: oldKey),
                         "the lock saved the journal with the key in force at that moment")
        XCTAssertFalse(db.isLoaded)
    }

    func testRekeyOfAnUnloadedJournalThrows() throws {
        let (db, _, _, _, _) = try journalWithHeldSave()
        try db.unload()
        XCTAssertThrowsError(try db.rekey(to: newKey))
        XCTAssertThrowsError(try db.saveNow(), "a save of a closed journal must not report success")
    }

    // MARK: - Finding 5: restore vs lock

    func testRestoreRacingALockFailsAndLeavesNothingWritableInMemory() throws {
        let (db, armed, reached, release, waiting) = try journalWithHeldSave()
        let image = try RaceFixture.journalImage(trades: 5)
        armed.value = true
        let lockDone = RaceFixture.inBackground { try? db.unload() }
        reached.wait("the lock's save")

        let restoreError = Shared<Error?>(nil)
        let restoreDone = RaceFixture.inBackground {
            do { try db.replaceContents(with: image) } catch { restoreError.value = error }
        }
        waiting.wait("restore reaching the database queue")
        release.fire()
        lockDone.wait("lock")
        restoreDone.wait("restore")

        XCTAssertNotNil(restoreError.value, "a restore that was never saved must not report success")
        let tables = try db.dbQueue.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM sqlite_master") }
        XCTAssertEqual(tables, 0, "the backup's rows must not sit in memory behind the lock screen")
        XCTAssertThrowsError(try db.dbQueue.write { try $0.execute(sql: "CREATE TABLE x(a)") }, "locked = read-only")
        // The journal on disk is the one saved at lock time (two trades).
        let reopened = try DatabaseManager(path: dbPath)
        try reopened.load(key: oldKey)
        XCTAssertEqual(try TradeRepository(database: reopened).count(), 2)
    }

    // MARK: - Full disk while opening (from the Greenwick review)

    func testASaveFailingWhileOpeningDoesNotFailTheOpen() throws {
        let (db, _, _, _, _) = try journalWithHeldSave()
        try db.unload()
        let before = journalFile

        let full = DatabaseManager.Hooks(willPersist: { throw POSIXError(.ENOSPC) })
        let reopened = try DatabaseManager(path: dbPath, hooks: full)
        XCTAssertNoThrow(try reopened.load(key: oldKey), "a full disk must not make a healthy journal unopenable")
        XCTAssertTrue(reopened.isLoaded)
        XCTAssertEqual(try TradeRepository(database: reopened).count(), 2)
        XCTAssertNotNil(reopened.lastSaveError, "the failed save is reported")
        XCTAssertEqual(journalFile, before, "the file on disk is untouched")
    }

    // MARK: - Finding 6: durable writes

    func testFilesAreForcedToDiskBeforeTheRenameAndTheFolderAfterIt() throws {
        let dir = try SecFixture.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("Dojix.sqlite").path
        try Data("old".utf8).write(to: URL(fileURLWithPath: path))
        let events = Shared<[String]>([])
        let sync = OwnerOnlyFile.FileSync(
            syncFile: { fd in
                let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
                events.value.append("file(\(content))")
                try OwnerOnlyFile.FileSync.system.syncFile(fd)
            },
            syncDirectory: { folder in
                let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
                events.value.append("folder(\(content))")
                XCTAssertEqual(folder, dir.path)
                OwnerOnlyFile.FileSync.system.syncDirectory(folder)
            })

        try OwnerOnlyFile.write(Data("new".utf8), to: path, sync: sync)

        XCTAssertEqual(events.value, ["file(old)", "folder(new)"],
                       "data flushed before the rename, the rename flushed before returning")
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "new")
    }
}
