import CryptoKit
import XCTest
@testable import Dojix

/// Tests for database encryption, export encryption, and certificate pinning infrastructure
final class SecurityTests: XCTestCase {

    // MARK: - Database Encryption

    private let sqliteMagic = Data([
        0x53, 0x51, 0x4C, 0x69, 0x74, 0x65, 0x20, 0x66,
        0x6F, 0x72, 0x6D, 0x61, 0x74, 0x20, 0x33, 0x00
    ])

    func testDatabaseEncryptionRoundTrip() throws {
        let dbPath = NSTemporaryDirectory() + "test_encrypt_\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: dbPath) }
        let key = SymmetricKey(size: .bits256)
        let payload = sqliteMagic + Data(repeating: 0xAB, count: 1000)

        // The file on disk is ciphertext only — no SQLite header, owner-only permissions
        try DatabaseEncryption.writeSealed(payload, key: key, to: dbPath)
        let onDisk = try Data(contentsOf: URL(fileURLWithPath: dbPath))
        XCTAssertNotEqual(onDisk.prefix(16), sqliteMagic)
        let perms = try FileManager.default.attributesOfItem(atPath: dbPath)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600)

        // Decrypting happens in memory and restores the original bytes
        XCTAssertEqual(try DatabaseEncryption.open(onDisk, key: key), payload)
    }

    func testDatabaseEncryptionSkipsAlreadyEncrypted() throws {
        let dir = NSTemporaryDirectory() + "test_skip_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let dbPath = dir + "/Dojix.sqlite"
        let encrypted = Data(repeating: 0xFF, count: 200)
        try encrypted.write(to: URL(fileURLWithPath: dbPath + ".unreadable-1"))

        // Already-encrypted (non-SQLite) copies are left exactly as they are
        DatabaseEncryption.sealStrayCopies(besides: dbPath, key: SymmetricKey(size: .bits256))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: dbPath + ".unreadable-1")), encrypted)
    }

    func testDatabaseEncryptionNoOpOnMissingFile() throws {
        let fakePath = NSTemporaryDirectory() + "nonexistent_\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: fakePath) }
        let key = SymmetricKey(size: .bits256)

        XCTAssertNoThrow(try DatabaseManager.encryptPlaintextFileInPlace(at: fakePath, key: key))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fakePath))
        // Loading with no file starts an empty journal
        let db = try DatabaseManager(path: fakePath)
        try db.load(key: key)
        XCTAssertEqual(try TradeRepository(database: db).count(), 0)
    }

    func testDatabaseEncryptionConsistentKey() throws {
        let dbPath = NSTemporaryDirectory() + "test_key_\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: dbPath) }
        let key = SymmetricKey(size: .bits256)
        let payload = sqliteMagic + Data(repeating: 0xCD, count: 500)

        // Round-trip twice with the same key
        try DatabaseEncryption.writeSealed(payload, key: key, to: dbPath)
        let once = try DatabaseEncryption.open(Data(contentsOf: URL(fileURLWithPath: dbPath)), key: key)
        try DatabaseEncryption.writeSealed(once, key: key, to: dbPath)
        let twice = try DatabaseEncryption.open(Data(contentsOf: URL(fileURLWithPath: dbPath)), key: key)
        XCTAssertEqual(twice, payload)

        // A different key can't open it
        XCTAssertThrowsError(try DatabaseEncryption.open(Data(contentsOf: URL(fileURLWithPath: dbPath)),
                                                         key: SymmetricKey(size: .bits256)))
    }

    // MARK: - Export Encryption

    func testExportEncryptionRoundTrip() throws {
        let original = "Trade data: GBPUSD, +$150.00, Session: London".data(using: .utf8)!
        let password = "TestPassword123!"

        let encrypted = try ExportEncryption.encrypt(data: original, password: password)
        let decrypted = try ExportEncryption.decrypt(data: encrypted, password: password)

        XCTAssertEqual(decrypted, original)
    }

    func testExportEncryptionWrongPassword() throws {
        let original = Data(repeating: 0x42, count: 500)
        let encrypted = try ExportEncryption.encrypt(data: original, password: "correct")

        XCTAssertThrowsError(try ExportEncryption.decrypt(data: encrypted, password: "wrong")) { error in
            XCTAssertTrue(error is ExportEncryption.ExportEncryptionError)
        }
    }

    func testExportEncryptionEmptyPassword() {
        let data = Data(repeating: 0x01, count: 100)

        XCTAssertThrowsError(try ExportEncryption.encrypt(data: data, password: "")) { error in
            guard let exportError = error as? ExportEncryption.ExportEncryptionError else {
                XCTFail("Expected ExportEncryptionError"); return
            }
            XCTAssertEqual(exportError, .invalidPassword)
        }
    }

    func testExportEncryptionMagicHeader() throws {
        let original = Data(repeating: 0x01, count: 100)
        let encrypted = try ExportEncryption.encrypt(data: original, password: "test")

        XCTAssertTrue(ExportEncryption.isEncrypted(encrypted))
        XCTAssertEqual(encrypted.prefix(4), Data([0x44, 0x4F, 0x4A, 0x58]))
    }

    func testExportEncryptionDetectsUnencrypted() {
        let plaintext = "Just a regular CSV file".data(using: .utf8)!
        XCTAssertFalse(ExportEncryption.isEncrypted(plaintext))
    }

    func testExportEncryptionTooShort() {
        let tiny = Data([0x44, 0x4F, 0x4A, 0x58, 0x01])

        XCTAssertThrowsError(try ExportEncryption.decrypt(data: tiny, password: "test")) { error in
            guard let exportError = error as? ExportEncryption.ExportEncryptionError else {
                XCTFail("Expected ExportEncryptionError"); return
            }
            XCTAssertEqual(exportError, .invalidFormat)
        }
    }

    func testExportEncryptionNotEncrypted() {
        let plain = Data(repeating: 0x00, count: 100)

        XCTAssertThrowsError(try ExportEncryption.decrypt(data: plain, password: "test")) { error in
            guard let exportError = error as? ExportEncryption.ExportEncryptionError else {
                XCTFail("Expected ExportEncryptionError"); return
            }
            XCTAssertEqual(exportError, .notEncrypted)
        }
    }

    func testExportEncryptionLargeData() throws {
        let largeData = Data(repeating: 0xAB, count: 1_000_000)
        let password = "LargeDataTest!2026"

        let encrypted = try ExportEncryption.encrypt(data: largeData, password: password)
        let decrypted = try ExportEncryption.decrypt(data: encrypted, password: password)

        XCTAssertEqual(decrypted, largeData)
        XCTAssertGreaterThan(encrypted.count, largeData.count)
    }

    func testExportEncryptionDifferentPasswordsDifferentOutput() throws {
        let data = Data(repeating: 0x42, count: 100)

        let enc1 = try ExportEncryption.encrypt(data: data, password: "password1")
        let enc2 = try ExportEncryption.encrypt(data: data, password: "password2")

        XCTAssertNotEqual(enc1, enc2)
    }

    func testExportEncryptionSamePasswordDifferentNonce() throws {
        let data = Data(repeating: 0x42, count: 100)
        let password = "samePassword"

        let enc1 = try ExportEncryption.encrypt(data: data, password: password)
        let enc2 = try ExportEncryption.encrypt(data: data, password: password)

        // Random salt + nonce means different ciphertext each time
        XCTAssertNotEqual(enc1, enc2)

        let dec1 = try ExportEncryption.decrypt(data: enc1, password: password)
        let dec2 = try ExportEncryption.decrypt(data: enc2, password: password)
        XCTAssertEqual(dec1, dec2)
        XCTAssertEqual(dec1, data)
    }

    func testExportEncryptionEncryptAndWrite() throws {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory() + "test_write_\(UUID().uuidString).dojix-enc")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let original = Data(repeating: 0x42, count: 200)
        try ExportEncryption.encryptAndWrite(data: original, to: tempURL, password: "test123")

        let written = try Data(contentsOf: tempURL)
        XCTAssertTrue(ExportEncryption.isEncrypted(written))

        let decrypted = try ExportEncryption.decrypt(data: written, password: "test123")
        XCTAssertEqual(decrypted, original)
    }

    // MARK: - Network Session

    func testSecureSessionConfiguration() {
        let session = SecureSession.make(timeout: 42)
        XCTAssertEqual(session.configuration.timeoutIntervalForRequest, 42)
        XCTAssertNil(session.configuration.urlCache)
        XCTAssertEqual(session.configuration.tlsMinimumSupportedProtocolVersion, .TLSv12)
    }
}
