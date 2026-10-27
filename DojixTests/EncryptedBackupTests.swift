import CryptoKit
import GRDB
import XCTest
@testable import Dojix

/// Password-protected backups: PBKDF2-SHA256 (600,000 rounds) + AES-256-GCM with the
/// header authenticated; restoring needs the password, and anything wrong leaves the
/// journal untouched. Plain backups and Dojix 1.x encrypted backups still restore.
/// All trades and passwords are fictional.
final class EncryptedBackupTests: XCTestCase {
    private var dir: URL!
    private var live: DatabaseManager!
    private let password = "fictional-pass-123"
    /// Fewer rounds keep most tests fast; one test checks the real default.
    private let fastRounds: UInt32 = 1_000

    override func setUpWithError() throws {
        dir = try SecFixture.scratchDirectory()
        live = try DatabaseManager(path: dir.appendingPathComponent("Dojix.sqlite").path)
        try live.load(key: SymmetricKey(size: .bits256))
        _ = try TradeRepository(database: live).bulkInsert([SecFixture.trade(ticket: 900), SecFixture.trade(ticket: 901)])
    }

    override func tearDownWithError() throws {
        live = nil
        try? FileManager.default.removeItem(at: dir)
    }

    private func source() throws -> DatabaseManager {
        let db = try DatabaseManager(inMemory: true)
        _ = try TradeRepository(database: db).bulkInsert((1...3).map { SecFixture.trade(ticket: Int64($0)) })
        return db
    }

    private func protectedBackup(rounds: UInt32? = nil) throws -> URL {
        let url = dir.appendingPathComponent("backup-\(UUID().uuidString).dojix")
        try BackupService.writeBackup(of: try source(), to: url, password: password, iterations: rounds ?? fastRounds)
        return url
    }

    private func liveTickets() throws -> [Int64] {
        try TradeRepository(database: live).fetchAll().map(\.ticket).sorted()
    }

    private func assertRefused(_ url: URL, password: String?, as expected: BackupService.BackupError,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try BackupService.restore(from: url, password: password, into: live), file: file, line: line) {
            XCTAssertEqual($0 as? BackupService.BackupError, expected, file: file, line: line)
        }
        XCTAssertEqual(try liveTickets(), [900, 901], "the journal must be untouched", file: file, line: line)
    }

    // MARK: - Round trip

    func testProtectedBackupRoundTripWithTheRealIterationCount() throws {
        let url = try protectedBackup(rounds: BackupEncryption.defaultIterations)
        let bytes = try Data(contentsOf: url)
        XCTAssertEqual(bytes.prefix(4), Data("DJXB".utf8))
        XCTAssertEqual(BackupEncryption.iterations(of: bytes), 600_000)
        XCTAssertFalse(DatabaseEncryption.isPlainSQLite(bytes), "not readable without the password")
        XCTAssertNil(bytes.range(of: Data("Sample (fictional)".utf8)), "no plaintext row data in the file")
        let perms = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600)
        XCTAssertEqual(BackupEncryption.kind(ofFileAt: url), .encrypted)

        let summary = try BackupService.restore(from: url, password: password, into: live)
        XCTAssertEqual(summary.trades, 3)
        XCTAssertEqual(try liveTickets(), [1, 2, 3])
    }

    func testPlainBackupStillRestoresWithoutAPassword() throws {
        let url = dir.appendingPathComponent("plain.dojix")
        try BackupService.writeBackup(of: try source(), to: url)
        XCTAssertTrue(DatabaseEncryption.isPlainSQLite(try Data(contentsOf: url)))
        XCTAssertEqual(BackupEncryption.kind(ofFileAt: url), .plain)
        _ = try BackupService.restore(from: url, into: live)
        XCTAssertEqual(try liveTickets(), [1, 2, 3])
    }

    // MARK: - Refusals (journal untouched)

    func testProtectedBackupAsksForItsPassword() throws {
        let url = try protectedBackup()
        assertRefused(url, password: nil, as: .passwordRequired)
        assertRefused(url, password: "", as: .passwordRequired)
    }

    func testWrongPasswordIsRefusedClearly() throws {
        let url = try protectedBackup()
        assertRefused(url, password: "not-the-password", as: .wrongPassword)
        XCTAssertTrue(BackupService.BackupError.wrongPassword.localizedDescription.contains("Wrong password"))
    }

    func testChangedHeaderIsRefused() throws {
        let original = try Data(contentsOf: try protectedBackup())
        // Salt byte, iteration count (still in range) and a ciphertext byte
        for (offset, newValue) in [(12, nil), (8, UInt8(0xE9)), (original.count - 20, nil)] as [(Int, UInt8?)] {
            var bytes = [UInt8](original)
            bytes[offset] = newValue ?? (bytes[offset] ^ 0x01)
            let url = dir.appendingPathComponent("tampered-\(offset).dojix")
            try Data(bytes).write(to: url)
            assertRefused(url, password: password, as: .wrongPassword)
        }
        // A version this build doesn't know
        var newer = [UInt8](original)
        newer[4] = 2
        let url = dir.appendingPathComponent("newer.dojix")
        try Data(newer).write(to: url)
        assertRefused(url, password: password, as: .newerVersion)
    }

    func testAbsurdIterationCountIsRefusedBeforeAnyWork() throws {
        let original = [UInt8](try Data(contentsOf: try protectedBackup()))
        for rounds: UInt32 in [4_000_000_000, 10_000_001, 0, 999] {
            var bytes = original
            withUnsafeBytes(of: rounds.bigEndian) { bytes.replaceSubrange(5..<9, with: $0) }
            let url = dir.appendingPathComponent("rounds-\(rounds).dojix")
            try Data(bytes).write(to: url)
            let started = Date()
            assertRefused(url, password: password, as: .damaged)
            XCTAssertLessThan(Date().timeIntervalSince(started), 1, "\(rounds) rounds must not be attempted")
        }
        XCTAssertThrowsError(try BackupEncryption.seal(Data([1]), password: password, iterations: 20_000_000))
    }

    func testTruncatedProtectedBackupIsRefused() throws {
        let url = dir.appendingPathComponent("short.dojix")
        try Data("DJXB".utf8 + [1, 0, 0]).write(to: url)
        assertRefused(url, password: password, as: .damaged)
    }

    func testEmptyPasswordNeverWritesABackup() throws {
        let url = dir.appendingPathComponent("empty-pw.dojix")
        XCTAssertThrowsError(try BackupService.writeBackup(of: try source(), to: url, password: "", iterations: fastRounds))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - Dojix 1.x encrypted backups (read only)

    func testLegacyEncryptedBackupStillRestores() throws {
        let image = try source().dbQueue.writeWithoutTransaction { db in try DatabaseManager.serialize(db) }
        let url = dir.appendingPathComponent("Dojix_Backup_old.dojix-enc")
        try ExportEncryption.encrypt(data: image, password: password).write(to: url)
        XCTAssertEqual(BackupEncryption.kind(ofFileAt: url), .legacyEncrypted)

        assertRefused(url, password: nil, as: .passwordRequired)
        assertRefused(url, password: "not-the-password", as: .wrongPassword)
        _ = try BackupService.restore(from: url, password: password, into: live)
        XCTAssertEqual(try liveTickets(), [1, 2, 3])
    }

    // MARK: - Backups of a locked journal

    func testNoBackupIsWrittenWhileTheJournalIsLocked() throws {
        try live.unload()
        let url = dir.appendingPathComponent("locked.dojix")
        XCTAssertThrowsError(try BackupService.writeBackup(of: live, to: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "an empty placeholder is never written as a backup")
    }

    // MARK: - Password rule (same as App Lock)

    func testPasswordRule() {
        XCTAssertEqual(PasswordRules.problem(password: "", confirmation: ""), "Password cannot be empty")
        XCTAssertEqual(PasswordRules.problem(password: "abcdefgh", confirmation: "abcdefgx"), "Passwords do not match")
        XCTAssertEqual(PasswordRules.problem(password: "short", confirmation: "short"), "Password must be at least 8 characters")
        XCTAssertNil(PasswordRules.problem(password: "abcdefgh", confirmation: "abcdefgh"))
        let long = String(repeating: "x", count: 129)
        XCTAssertNotNil(PasswordRules.problem(password: long, confirmation: long))
    }
}
