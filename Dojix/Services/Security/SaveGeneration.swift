import CryptoKit
import Foundation
import Security
import os

/// One save of the journal, stored (authenticated) in the header of the sealed journal
/// file (see `DatabaseEncryption.sealJournal`):
/// - `epoch`: a random 16-byte ID of the journal's line of saves ("branch"). A new one
///   starts with a new journal, and whenever the user chooses to open an older copy, so
///   the saves that copy replaced can never be passed off as current later.
/// - `generation`: goes up by one with every save, and never down.
/// - `savedAt`: when (whole seconds).
struct JournalStamp: Equatable, Sendable {
    static let epochLength = 16

    var epoch: Data
    var generation: UInt64
    var savedAt: Date

    init(epoch: Data, generation: UInt64, savedAt: Date) {
        self.epoch = epoch
        self.generation = generation
        // Whole seconds: the same value survives the file header and the Keychain item.
        self.savedAt = Date(timeIntervalSince1970: savedAt.timeIntervalSince1970.rounded(.down))
    }

    /// A fresh random epoch.
    static func newEpoch() -> Data {
        SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }
    }
}

/// What this Mac last saved: the stamp, plus a SHA-256 of the sealed file it wrote.
struct SaveRecord: Equatable, Sendable {
    var stamp: JournalStamp
    var fileHash: Data

    init(stamp: JournalStamp, sealedFile: Data) {
        self.stamp = stamp
        self.fileHash = Data(SHA256.hash(data: sealedFile))
    }

    init(stamp: JournalStamp, fileHash: Data) {
        self.stamp = stamp
        self.fileHash = fileHash
    }

    /// Whether `sealedFile` is exactly the file this record describes.
    func matches(_ sealedFile: Data) -> Bool {
        Data(SHA256.hash(data: sealedFile)) == fileHash
    }
}

/// Rollback protection: the last save this Mac made, kept in the Keychain (same service
/// as the database key, its own account, "when unlocked, this device only"). A journal
/// file on disk that isn't that save or a later one of the same epoch is not opened
/// silently (see `DatabaseManager.load`).
///
/// A Keychain that can't be written is logged and otherwise ignored: saving the journal
/// never fails because of this record.
struct SaveGenerationStore: Sendable {
    static let account = "journal_save_generation"
    private static let logger = Logger(subsystem: "com.dojix", category: "SaveGeneration")

    let store: any SecretStore

    /// The record is written on every save, also while locking (on the main thread): it
    /// never shows a Keychain dialog, which would keep the journal on screen. A write
    /// that fails is tolerated (see `record`).
    init(store: any SecretStore = KeychainSecretStore(allowsUserInteraction: false)) {
        self.store = store
    }

    /// The last save this Mac recorded. nil when there is none (first launch of a build
    /// with rollback protection, or after "erase all"), or when the item can't be read
    /// or is damaged (logged): then any journal file is accepted, as before.
    func lastSaved() -> SaveRecord? {
        let (value, status) = store.read(Self.account)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let value else {
            Self.logger.error("Could not read the last save record (status \(status))")
            return nil
        }
        guard let record = Self.decode(value) else {
            Self.logger.error("The stored save record is damaged; ignoring it")
            return nil
        }
        return record
    }

    /// Record `record` as the latest save. Returns false (and logs) if the Keychain
    /// refused it; the caller carries on.
    @discardableResult
    func record(_ record: SaveRecord) -> Bool {
        let ok = store.write(Self.account, Self.encode(record))
        if !ok {
            Self.logger.error("Could not record save generation \(record.stamp.generation) in the Keychain")
        }
        return ok
    }

    func delete() {
        store.delete(Self.account)
    }

    /// "v2:<epoch hex>:<generation>:<seconds since 1970>:<SHA-256 hex of the sealed file>"
    static func encode(_ record: SaveRecord) -> String {
        "v2:\(record.stamp.epoch.hexString):\(record.stamp.generation):"
            + "\(Int64(record.stamp.savedAt.timeIntervalSince1970)):\(record.fileHash.hexString)"
    }

    static func decode(_ value: String) -> SaveRecord? {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 5, parts[0] == "v2",
              let epoch = Data(hexString: String(parts[1])), epoch.count == JournalStamp.epochLength,
              let generation = UInt64(parts[2]), let seconds = Int64(parts[3]),
              let hash = Data(hexString: String(parts[4])), hash.count == SHA256.byteCount else { return nil }
        let stamp = JournalStamp(epoch: epoch, generation: generation,
                                 savedAt: Date(timeIntervalSince1970: TimeInterval(seconds)))
        return SaveRecord(stamp: stamp, fileHash: hash)
    }
}

/// The journal file is not the last one this Mac saved (nor a later save of it): an
/// older copy was put back, or a copy from a line of saves the user abandoned. Thrown by
/// `DatabaseManager.load` before anything is decrypted into the app or written.
struct OlderJournalError: LocalizedError, Equatable {
    /// The file's own stamp; nil for a file sealed before save stamps existed, or a
    /// plaintext file left by an older build (both count as generation 0).
    let fileStamp: JournalStamp?
    /// The latest save this Mac recorded.
    let lastSaved: JournalStamp

    var errorDescription: String? {
        "This journal is older than the last one this Mac saved (saved "
            + "\(lastSaved.savedAt.formatted(date: .abbreviated, time: .shortened))). Open it anyway?"
    }
}

extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }

    init?(hexString: String) {
        guard hexString.count.isMultiple(of: 2), hexString.allSatisfy(\.isHexDigit) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
