import CryptoKit
import Foundation

/// Password-protected backups.
///
/// File format (version 1), all integers big-endian:
/// `"DJXB" | version (1 byte) | PBKDF2 iterations (UInt32) | salt (16 bytes) | AES-GCM box`
/// where the box is nonce (12) | ciphertext | tag (16) of the backup's SQLite image. The
/// key is PBKDF2-SHA256(password, salt, iterations), 600,000 iterations for every new
/// backup. The 25-byte header is authenticated as AES-GCM associated data, so changing
/// any byte of it (version, iteration count, salt) makes the file fail to open.
///
/// When reading, the iteration count must lie in `iterationRange`: a file asking for
/// billions of rounds (hours of work) or for almost none is refused before any key is
/// derived. Backups from Dojix 1.x ("DOJX", 100,000 rounds, see `ExportEncryption`) are
/// read only; new ones always use this format.
enum BackupEncryption {
    static let magic = Data("DJXB".utf8)
    static let formatVersion: UInt8 = 1
    static let headerLength = 4 + 1 + 4 + 16
    /// OWASP 2023 recommendation for PBKDF2-HMAC-SHA256 (the same as App Lock).
    static let defaultIterations: UInt32 = 600_000
    /// Accepted when reading.
    static let iterationRange: ClosedRange<UInt32> = 1_000...10_000_000

    /// What a backup file is, judged by its first bytes.
    enum Kind: Equatable, Sendable {
        /// An unencrypted SQLite database (or not a backup at all: validated later).
        case plain
        /// Password-protected, this format.
        case encrypted
        /// Password-protected by Dojix 1.x ("DOJX").
        case legacyEncrypted

        var needsPassword: Bool { self != .plain }
    }

    static func kind(of data: Data) -> Kind {
        let head = data.prefix(4)
        if head == magic { return .encrypted }
        if head == ExportEncryption.magic { return .legacyEncrypted }
        return .plain
    }

    /// The kind of the file at `url` (reads only its first 4 bytes).
    static func kind(ofFileAt url: URL) -> Kind {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .plain }
        defer { try? handle.close() }
        return kind(of: (try? handle.read(upToCount: 4)) ?? Data())
    }

    // MARK: - Seal / open

    /// Encrypt a backup image with `password`.
    static func seal(_ image: Data, password: String, iterations: UInt32 = defaultIterations) throws -> Data {
        guard !password.isEmpty, iterationRange.contains(iterations) else { throw BackupService.BackupError.passwordRequired }
        let salt = KeyDerivation.generateSalt()
        var header = magic
        header.append(formatVersion)
        withUnsafeBytes(of: iterations.bigEndian) { header.append(contentsOf: $0) }
        header.append(salt)
        let key = try deriveKey(password: password, salt: salt, iterations: iterations)
        guard let combined = try? AES.GCM.seal(image, using: key, authenticating: header).combined else {
            throw DatabaseEncryption.EncryptionError.encryptionFailed
        }
        return header + combined
    }

    /// Decrypt a password-protected backup (this format or Dojix 1.x's).
    /// - Throws: `BackupError.passwordRequired` (no password), `.wrongPassword` (wrong
    ///   password, or a file that was changed), `.newerVersion`, `.damaged`.
    static func open(_ data: Data, password: String) throws -> Data {
        guard !password.isEmpty else { throw BackupService.BackupError.passwordRequired }
        switch kind(of: data) {
        case .plain:
            return data
        case .legacyEncrypted:
            return try openLegacy(data, password: password)
        case .encrypted:
            break
        }
        let bytes = [UInt8](data)
        guard bytes.count >= headerLength + 12 + 16 else { throw BackupService.BackupError.damaged }
        guard bytes[4] == formatVersion else {
            throw bytes[4] > formatVersion ? BackupService.BackupError.newerVersion : BackupService.BackupError.damaged
        }
        let iterations = bytes[5..<9].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard iterationRange.contains(iterations) else { throw BackupService.BackupError.damaged }
        let header = Data(bytes[0..<headerLength])
        let salt = Data(bytes[9..<headerLength])
        let key = try deriveKey(password: password, salt: salt, iterations: iterations)
        do {
            let box = try AES.GCM.SealedBox(combined: Data(bytes[headerLength...]))
            return try AES.GCM.open(box, using: key, authenticating: header)
        } catch {
            throw BackupService.BackupError.wrongPassword
        }
    }

    /// Iteration count in a backup's header (nil if it isn't this format).
    static func iterations(of data: Data) -> UInt32? {
        guard kind(of: data) == .encrypted, data.count >= headerLength else { return nil }
        return [UInt8](data.prefix(9))[5..<9].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    // MARK: - Private

    private static func openLegacy(_ data: Data, password: String) throws -> Data {
        do {
            return try ExportEncryption.decrypt(data: data, password: password)
        } catch ExportEncryption.ExportEncryptionError.wrongPassword {
            throw BackupService.BackupError.wrongPassword
        } catch {
            throw BackupService.BackupError.damaged
        }
    }

    private static func deriveKey(password: String, salt: Data, iterations: UInt32) throws -> SymmetricKey {
        guard let derived = KeyDerivation.deriveKey(password: password, salt: salt, iterations: iterations) else {
            throw BackupService.BackupError.wrongPassword
        }
        return SymmetricKey(data: derived)
    }
}

/// The password rule for App Lock and for password-protected backups.
enum PasswordRules {
    static let minimumLength = 8
    static let maximumLength = 128

    /// Why `password` can't be used (nil = fine). `confirmation` must match it.
    static func problem(password: String, confirmation: String) -> String? {
        if password.isEmpty { return "Password cannot be empty" }
        if password != confirmation { return "Passwords do not match" }
        if password.count < minimumLength { return "Password must be at least \(minimumLength) characters" }
        if password.count > maximumLength { return "Password must be at most \(maximumLength) characters" }
        return nil
    }
}
