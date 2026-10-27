import CryptoKit
import GRDB
import XCTest
@testable import Dojix

/// A restored backup is validated row by row and never copied over the journal
/// (F2, F6, F7, F8): hostile files are refused and the journal is left unchanged.
final class RestoreValidationTests: XCTestCase {
    private var dir: URL!
    private var live: DatabaseManager!

    override func setUpWithError() throws {
        dir = try SecFixture.scratchDirectory()
        live = try DatabaseManager(path: dir.appendingPathComponent("Dojix.sqlite").path)
        try live.load(key: SymmetricKey(size: .bits256))
        try TradeRepository(database: live).bulkInsert([SecFixture.trade(ticket: 900), SecFixture.trade(ticket: 901)])
    }

    override func tearDownWithError() throws {
        live = nil
        try? FileManager.default.removeItem(at: dir)
    }

    /// A genuine backup (three trades), optionally tampered with raw SQL afterwards.
    private func makeBackup(_ tamper: String? = nil, arguments: StatementArguments = []) throws -> URL {
        let source = try DatabaseManager(inMemory: true)
        try TradeRepository(database: source).bulkInsert((1...3).map { SecFixture.trade(ticket: Int64($0)) })
        let url = dir.appendingPathComponent("backup-\(UUID().uuidString).dojix")
        try BackupService.writeBackup(of: source, to: url)
        if let tamper {
            let file = try DatabaseQueue(path: url.path)
            try file.writeWithoutTransaction { db in try db.execute(sql: tamper, arguments: arguments) }
            try file.close()
        }
        return url
    }

    private func liveTickets() throws -> [Int64] {
        try TradeRepository(database: live).fetchAll().map(\.ticket).sorted()
    }

    private func assertRefused(_ url: URL, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertThrowsError(try BackupService.restore(from: url, into: live), file: file, line: line)
        XCTAssertEqual(try liveTickets(), [900, 901], "the journal must be unchanged", file: file, line: line)
    }

    func testGenuineBackupRestoresInPlace() throws {
        let summary = try BackupService.restore(from: try makeBackup(), into: live)
        XCTAssertEqual(summary.trades, 3)
        XCTAssertEqual(try liveTickets(), [1, 2, 3])
        XCTAssertFalse(FileManager.default.fileExists(atPath: live.databasePath + ".pre-restore-backup"),
                       "no plaintext safety copy is written any more")
        XCTAssertEqual(SecFixture.plaintextFiles(in: dir).filter { !$0.hasPrefix("backup-") }, [])
    }

    func testBackupFromAnOlderBuildInWALModeRestores() throws {
        // Older builds copied their WAL-mode database file as the backup
        let url = dir.appendingPathComponent("old.dojix")
        try SecFixture.writeLegacyPlaintextJournal(at: url.path, trades: [SecFixture.trade(ticket: 5)])
        let check = try DatabaseQueue(path: url.path)
        try check.writeWithoutTransaction { db in _ = try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)") }
        try check.close()
        _ = try BackupService.restore(from: url, into: live)
        XCTAssertEqual(try liveTickets(), [5])
    }

    func testHugeDurationIsRefused() throws {
        // F6: two durations near Int.max made the dashboard's sum trap on every launch
        try assertRefused(try makeBackup("UPDATE trades SET durationMin = ?", arguments: [Int.max - 1]))
    }

    func testTraversalScreenshotNameIsRefused() throws {
        // F8: ".." would have resolved to the shared Screenshots folder
        try assertRefused(try makeBackup("UPDATE trades SET screenshots = '..' WHERE ticket = 1"))
        try assertRefused(try makeBackup("UPDATE trades SET screenshots = '.hidden.jpg' WHERE ticket = 1"))
    }

    func testControlCharacterInSymbolIsRefused() throws {
        // F7: a bare CR in a symbol split exported CSV rows
        try assertRefused(try makeBackup("UPDATE trades SET symbol = 'EURUSD' || char(13) || '=HYPERLINK(1)' WHERE ticket = 1"))
    }

    func testTinyOrHugeValuesAreRefused() throws {
        // F5: lots of 1e-15 made the size-discipline ratio overflow Int
        try assertRefused(try makeBackup("UPDATE trades SET lots = 1e-15 WHERE ticket = 1"))
        try assertRefused(try makeBackup("UPDATE trades SET netProfit = '1e30' WHERE ticket = 2"))
        try assertRefused(try makeBackup("UPDATE trades SET hour = 99 WHERE ticket = 3"))
        try assertRefused(try makeBackup("UPDATE trades SET maePips = 1e300 WHERE ticket = 3"))
    }

    func testTriggersViewsAndForeignTablesAreRefused() throws {
        try assertRefused(try makeBackup("CREATE TRIGGER t AFTER INSERT ON settings BEGIN DELETE FROM trades; END"))
        try assertRefused(try makeBackup("CREATE VIEW v AS SELECT * FROM trades"))
        try assertRefused(try makeBackup("CREATE TABLE extra(x)"))
    }

    func testAllowedTableWithDifferentShapeIsRefused() throws {
        // An allowed table name can still carry extra columns, a trigger or an extra index
        try assertRefused(try makeBackup("ALTER TABLE trades ADD COLUMN payload TEXT DEFAULT 'x'"))
        try assertRefused(try makeBackup("CREATE TRIGGER t2 BEFORE UPDATE ON trades BEGIN SELECT 1; END"))
        try assertRefused(try makeBackup("CREATE INDEX idx_trades_symbol2 ON trades(lower(symbol))"))
        try assertRefused(try makeBackup("""
            DROP INDEX idx_checkpoints_date; DROP TABLE strategy_checkpoints;
            CREATE TABLE strategy_checkpoints (id INTEGER PRIMARY KEY AUTOINCREMENT, date DATE NOT NULL,
              title TEXT NOT NULL, description TEXT NOT NULL DEFAULT '', createdAt DATETIME NOT NULL, extra BLOB);
            CREATE INDEX idx_checkpoints_date ON strategy_checkpoints(date)
            """))
    }

    func testRestoredJournalHasExactlyDojixSchema() throws {
        _ = try BackupService.restore(from: try makeBackup(), into: live)
        let reference = try DatabaseManager(inMemory: true)
        let schema = "SELECT type, name, tbl_name, sql FROM sqlite_master ORDER BY type, name"
        XCTAssertEqual(try live.dbQueue.read { try Row.fetchAll($0, sql: schema) },
                       try reference.dbQueue.read { try Row.fetchAll($0, sql: schema) })
    }

    func testNewerOrForeignMigrationsAreRefused() throws {
        let url = try makeBackup("INSERT INTO grdb_migrations (identifier) VALUES ('v99_future')")
        XCTAssertThrowsError(try BackupService.restore(from: url, into: live)) {
            XCTAssertEqual($0 as? BackupService.BackupError, .newerVersion)
        }
        XCTAssertEqual(try liveTickets(), [900, 901])
    }

    func testNonDatabaseFilesAreRefused() throws {
        let junk = dir.appendingPathComponent("junk.dojix")
        try Data("not a database at all, just some text".utf8).write(to: junk)
        try assertRefused(junk)

        // A SQLite header followed by garbage
        let damaged = dir.appendingPathComponent("damaged.dojix")
        try (DatabaseEncryption.sqliteMagic + Data(repeating: 0x41, count: 8192)).write(to: damaged)
        try assertRefused(damaged)
    }

    func testFreeTextIsCleanedButKept() throws {
        let url = try makeBackup("UPDATE trades SET notes = 'line one' || char(10) || 'two' || char(13) || '!', tags = 'a' || char(7) || 'b' WHERE ticket = 1")
        _ = try BackupService.restore(from: url, into: live)
        let trade = try XCTUnwrap(try TradeRepository(database: live).fetchAll().first { $0.ticket == 1 })
        XCTAssertEqual(trade.notes, "line one\ntwo!")
        XCTAssertEqual(trade.tags, "ab")
    }
}
