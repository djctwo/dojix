import CryptoKit
import Foundation
import os

/// AES-256-GCM encryption of the journal files at rest.
///
/// The journal database lives in memory while Dojix runs (see `DatabaseManager`); on disk
/// there is only the sealed copy written here. Journal file format (`sealJournal`): a
/// 37-byte header (magic, version, epoch, save generation, save time) followed by the AES-GCM
/// combined box (nonce | ciphertext | tag) of the SQLite image, with the header bound as
/// associated data. Journals from earlier builds are the bare box (no header) and still
/// open; they count as save generation 0.
enum DatabaseEncryption {
    private static let logger = Logger(subsystem: "com.dojix", category: "DatabaseEncryption")

    /// SQLite file magic header: "SQLite format 3\0"
    static let sqliteMagic = Data([
        0x53, 0x51, 0x4C, 0x69, 0x74, 0x65, 0x20, 0x66,
        0x6F, 0x72, 0x6D, 0x61, 0x74, 0x20, 0x33, 0x00
    ])

    /// Whether `data` is an unencrypted SQLite database image.
    static func isPlainSQLite(_ data: Data) -> Bool {
        data.count >= 16 && data.prefix(16) == sqliteMagic
    }

    /// Whether `data` is an unencrypted SQLite write-ahead log.
    static func isPlainWAL(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        let head = [UInt8](data.prefix(4))
        return head == [0x37, 0x7F, 0x06, 0x82] || head == [0x37, 0x7F, 0x06, 0x83]
    }

    // MARK: - Seal / open

    static func seal(_ plaintext: Data, key: SymmetricKey) throws -> Data {
        do {
            guard let combined = try AES.GCM.seal(plaintext, using: key).combined else {
                throw EncryptionError.encryptionFailed
            }
            return combined
        } catch let error as EncryptionError {
            throw error
        } catch {
            throw EncryptionError.encryptionFailed
        }
    }

    /// Decrypt a sealed file: the journal format with its stamp header (`sealJournal`)
    /// or the plain AES-GCM box (screenshots' body, stray copies, older journals).
    static func open(_ sealed: Data, key: SymmetricKey) throws -> Data {
        try openJournal(sealed, key: key).image
    }

    /// Plain AES-GCM box (nonce | ciphertext | tag), no header.
    private static func openBox(_ sealed: Data, key: SymmetricKey, authenticating header: Data? = nil) throws -> Data {
        do {
            let box = try AES.GCM.SealedBox(combined: sealed)
            if let header { return try AES.GCM.open(box, using: key, authenticating: header) }
            return try AES.GCM.open(box, using: key)
        } catch {
            throw EncryptionError.decryptionFailed
        }
    }

    // MARK: - Journal file (with save stamp)

    /// "DJXJ" | version (1) | epoch (16 bytes) | generation (UInt64 BE) |
    /// saved at (Int64 BE, seconds since 1970)
    static let journalMagic = Data("DJXJ".utf8)
    static let journalFormatVersion: UInt8 = 1
    static let journalHeaderLength = 4 + 1 + JournalStamp.epochLength + 8 + 8

    /// Seal the journal image with its save stamp. The header is authenticated as
    /// AES-GCM associated data, so changing the epoch, generation or date breaks decryption.
    static func sealJournal(_ image: Data, key: SymmetricKey, stamp: JournalStamp) throws -> Data {
        guard stamp.epoch.count == JournalStamp.epochLength else { throw EncryptionError.encryptionFailed }
        var header = journalMagic
        header.append(journalFormatVersion)
        header.append(stamp.epoch)
        withUnsafeBytes(of: stamp.generation.bigEndian) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: Int64(stamp.savedAt.timeIntervalSince1970).bigEndian) { header.append(contentsOf: $0) }
        do {
            guard let combined = try AES.GCM.seal(image, using: key, authenticating: header).combined else {
                throw EncryptionError.encryptionFailed
            }
            return header + combined
        } catch let error as EncryptionError {
            throw error
        } catch {
            throw EncryptionError.encryptionFailed
        }
    }

    /// Open a journal file. `stamp` is nil for a file sealed before save stamps existed
    /// (a plain AES-GCM box), which counts as generation 0.
    static func openJournal(_ sealed: Data, key: SymmetricKey) throws -> (image: Data, stamp: JournalStamp?) {
        let bytes = [UInt8](sealed)
        if bytes.count >= journalHeaderLength + 28, Data(bytes[0..<4]) == journalMagic,
           bytes[4] == journalFormatVersion {
            let header = Data(bytes[0..<journalHeaderLength])
            if let image = try? openBox(Data(bytes[journalHeaderLength...]), key: key, authenticating: header) {
                let epoch = Data(bytes[5..<21])
                let generation = bytes[21..<29].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
                let seconds = Int64(bitPattern: bytes[29..<37].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) })
                let stamp = JournalStamp(epoch: epoch, generation: generation,
                                         savedAt: Date(timeIntervalSince1970: TimeInterval(seconds)))
                return (image, stamp)
            }
            // Otherwise: an older plain box whose random nonce happens to start like a
            // header (practically never); try it as one below.
        }
        do {
            return (try openBox(sealed, key: key), nil)
        } catch {
            logger.error("Database decryption failed")
            throw error
        }
    }

    /// Seal the journal with `stamp` and atomically replace the file at `path` (0600).
    /// Returns the sealed bytes written.
    @discardableResult
    static func writeJournal(_ image: Data, key: SymmetricKey, stamp: JournalStamp, to path: String) throws -> Data {
        let sealed = try sealJournal(image, key: key, stamp: stamp)
        try writeAtomically(sealed, to: path)
        return sealed
    }

    /// Seal `plaintext` and atomically replace the file at `path` with the ciphertext.
    /// The file is created owner-only (0600) and flushed to disk before the rename.
    static func writeSealed(_ plaintext: Data, key: SymmetricKey, to path: String) throws {
        let sealed = try seal(plaintext, key: key)
        try writeAtomically(sealed, to: path)
    }

    /// Atomic, symlink-safe replace with an owner-only (0600) file (see `OwnerOnlyFile`).
    static func writeAtomically(_ data: Data, to path: String) throws {
        try OwnerOnlyFile.write(data, to: path, failure: EncryptionError.encryptionFailed)
    }

    // MARK: - Stray copies

    /// Files next to the database that belong to it: legacy `-wal`/`-shm`, the
    /// `.pre-restore-backup` copy older builds kept, `.unreadable-*` copies set aside by
    /// recovery, and an interrupted `.saving` temp file. Throws when the folder exists
    /// but can't be listed (none of them can be ruled out); a missing folder has none.
    static func strayFiles(besides databasePath: String) throws -> [URL] {
        let url = URL(fileURLWithPath: databasePath)
        let dir = url.deletingLastPathComponent()
        let base = url.lastPathComponent
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        return names
            .filter { $0 != base && ($0.hasPrefix(base + ".") || $0.hasPrefix(base + "-")) }
            .sorted()
            .map { dir.appendingPathComponent($0) }
    }

    /// Encrypt every plaintext copy of the journal lying next to the database (older
    /// builds left a `.pre-restore-backup`, and recovery sets damaged files aside as
    /// `.unreadable-*`). They are sealed in place with the database key rather than
    /// deleted, so nothing is destroyed; "Erase all local data" deletes them.
    /// The live database's own `-wal`/`-shm` are not touched here.
    static func sealStrayCopies(besides databasePath: String, key: SymmetricKey) {
        let base = URL(fileURLWithPath: databasePath).lastPathComponent
        for file in (try? strayFiles(besides: databasePath)) ?? [] {
            let name = file.lastPathComponent
            if name == base + "-wal" || name == base + "-shm" { continue }
            if name.hasSuffix(".saving") || name.hasSuffix("-shm") {
                // An interrupted save (ciphertext) or a WAL index (no data of its own)
                try? FileManager.default.removeItem(at: file)
                continue
            }
            guard let data = try? Data(contentsOf: file), isPlainSQLite(data) || isPlainWAL(data) else { continue }
            do {
                try writeSealed(data, key: key, to: file.path)
                logger.info("Encrypted a plaintext copy left next to the database: \(name)")
            } catch {
                logger.error("Could not encrypt \(name): \(error.localizedDescription)")
            }
        }
    }

    /// Key rotation: re-seal every encrypted copy next to the database that opens with
    /// `old` (but not already with `new`) so it opens with `new`. Returns what may still
    /// need `old`: copies that could not be read, or opened with `old` but could not be
    /// re-written, or the folder itself if it could not be listed. The caller keeps
    /// `old` while this list is not empty.
    @discardableResult
    static func resealStrayCopies(besides databasePath: String, from old: SymmetricKey, to new: SymmetricKey) -> [URL] {
        let base = URL(fileURLWithPath: databasePath).lastPathComponent
        let files: [URL]
        do {
            files = try strayFiles(besides: databasePath)
        } catch {
            logger.error("Could not list the data folder to re-seal copies: \(error.localizedDescription)")
            return [URL(fileURLWithPath: databasePath).deletingLastPathComponent()]
        }
        var pending: [URL] = []
        for file in files {
            let name = file.lastPathComponent
            if name == base + "-wal" || name == base + "-shm" || name.hasSuffix(".saving") { continue }
            guard let data = try? Data(contentsOf: file) else {
                logger.error("Could not read \(name) to re-seal it")
                pending.append(file)
                continue
            }
            guard !isPlainSQLite(data), !isPlainWAL(data),
                  (try? open(data, key: new)) == nil,
                  let plain = try? open(data, key: old) else { continue }
            do {
                try writeSealed(plain, key: new, to: file.path)
            } catch {
                logger.error("Could not re-seal \(name): \(error.localizedDescription)")
                pending.append(file)
            }
        }
        return pending
    }

    // MARK: - Errors

    enum EncryptionError: LocalizedError {
        case decryptionFailed
        case encryptionFailed
        case keyUnavailable

        var errorDescription: String? {
            switch self {
            case .keyUnavailable:
                "The database key could not be read from the Keychain."
            case .decryptionFailed:
                "Failed to decrypt the database. The encryption key may have changed."
            case .encryptionFailed:
                "Failed to encrypt the database."
            }
        }
    }
}
