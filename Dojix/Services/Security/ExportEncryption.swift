import CryptoKit
import Foundation

/// Reader for password-protected backups made by Dojix 1.x (read-only legacy support).
///
/// Format: [4-byte magic "DOJX"] [16-byte salt] [AES-GCM sealed box (nonce + ciphertext + tag)],
/// key = PBKDF2-SHA256(password, salt, 100,000 iterations). Dojix no longer writes this
/// format: new password-protected backups use `BackupEncryption` (600,000 iterations,
/// authenticated header).
enum ExportEncryption {
    /// Magic bytes identifying a Dojix 1.x encrypted export
    static let magic = Data([0x44, 0x4F, 0x4A, 0x58]) // "DOJX"
    /// Iterations Dojix 1.x used.
    static let legacyIterations: UInt32 = 100_000

    // MARK: - Decrypt

    /// Decrypt a Dojix 1.x encrypted export.
    static func decrypt(data: Data, password: String) throws -> Data {
        // Minimum size: 4 magic + 16 salt + 12 nonce + 16 tag = 48 bytes
        guard data.count >= 48 else {
            throw ExportEncryptionError.invalidFormat
        }
        guard data.prefix(4) == magic else {
            throw ExportEncryptionError.notEncrypted
        }
        let bytes = [UInt8](data)
        let key = try legacyKey(password: password, salt: Data(bytes[4..<20]))
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: Data(bytes[20...]))
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw ExportEncryptionError.wrongPassword
        }
    }

    // MARK: - Detection

    /// Check if data appears to be a Dojix 1.x encrypted export
    static func isEncrypted(_ data: Data) -> Bool {
        data.count >= 48 && data.prefix(4) == magic
    }

    /// Check if a file at the given path is a Dojix 1.x encrypted export
    static func isEncryptedFile(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 4)) == magic
    }

    // MARK: - Key Derivation

    /// The Dojix 1.x key: PBKDF2-SHA256, 100,000 iterations.
    static func legacyKey(password: String, salt: Data) throws -> SymmetricKey {
        guard !password.isEmpty else { throw ExportEncryptionError.invalidPassword }
        guard let derived = KeyDerivation.deriveKey(password: password, salt: salt, iterations: legacyIterations) else {
            throw ExportEncryptionError.keyDerivationFailed
        }
        return SymmetricKey(data: derived)
    }

    // MARK: - Errors

    enum ExportEncryptionError: LocalizedError {
        case encryptionFailed
        case invalidFormat
        case notEncrypted
        case wrongPassword
        case invalidPassword
        case keyDerivationFailed

        var errorDescription: String? {
            switch self {
            case .encryptionFailed: "Failed to encrypt the export data."
            case .invalidFormat: "The file format is not recognized."
            case .notEncrypted: "This file is not encrypted."
            case .wrongPassword: "Incorrect password. Please try again."
            case .invalidPassword: "Password cannot be empty."
            case .keyDerivationFailed: "Failed to derive encryption key."
            }
        }
    }
}
