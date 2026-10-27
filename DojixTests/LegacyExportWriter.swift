import CryptoKit
import Foundation
@testable import Dojix

/// The Dojix 1.x encrypted-export writer, kept in the tests only: the app reads this
/// format (old backups still restore) but never writes it any more.
extension ExportEncryption {
    static func encrypt(data: Data, password: String) throws -> Data {
        guard !password.isEmpty else { throw ExportEncryptionError.invalidPassword }
        let salt = KeyDerivation.generateSalt()
        let key = try legacyKey(password: password, salt: salt)
        guard let sealed = try AES.GCM.seal(data, using: key).combined else {
            throw ExportEncryptionError.encryptionFailed
        }
        return magic + salt + sealed
    }

    static func encryptAndWrite(data: Data, to url: URL, password: String) throws {
        try OwnerOnlyFile.write(try encrypt(data: data, password: password), to: url)
    }
}
