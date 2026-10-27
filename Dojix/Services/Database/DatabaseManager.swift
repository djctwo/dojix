import CryptoKit
import Foundation
import GRDB
import SQLite3
import os

/// Owns the journal database.
///
/// The decrypted journal only ever exists in memory. On disk there is a single
/// AES-256-GCM sealed file (`Dojix.sqlite`): after every committed write the in-memory
/// database is serialized, sealed with the database key and atomically written over it.
/// A plaintext SQLite file is never written next to it, so a crash, force quit or power
/// loss leaves nothing readable behind.
///
/// Lifecycle: `init()` creates an empty, read-only, *unloaded* database. Nothing is read
/// from disk until `load(key:)` is called with the database key, which `AppState` only
/// obtains after the App Lock password has been verified (it unwraps the key).
/// `unload()` saves, then wipes the in-memory copy (used when the app locks itself).
///
/// Rollback protection: every save carries an epoch (random ID of the line of saves) and a
/// generation number one higher than the last, stored in the sealed file's authenticated
/// header; the Keychain (`SaveGenerationStore`) keeps the last save's stamp and the hash
/// of the file written. `load` refuses any other file (an older one, one from another
/// epoch, or a different file with the same generation) unless the caller explicitly
/// allows it (`OlderJournalError`); then a new epoch starts and the count goes on.
final class DatabaseManager: @unchecked Sendable {
    // @unchecked: mutable state lives in `state` (a lock) and GRDB's serialized queue.

    /// In-memory database. Use `dbQueue.read/write` as with any GRDB database.
    let dbQueue: DatabaseQueue
    /// Path of the encrypted database file (a scratch path for test databases).
    let databasePath: String
    /// False for test databases (`init(inMemory:)`), which are never written to disk.
    let isPersistent: Bool

    private static let logger = Logger(subsystem: "com.dojix", category: "Database")
    private let state = OSAllocatedUnfairLock(initialState: PersistState())
    private let writer = DispatchQueue(label: "com.dojix.database.persist", qos: .userInitiated)
    private var commitObserver: CommitObserver?
    /// Where the latest save generation is recorded (nil: not tracked, e.g. tests).
    private let generations: SaveGenerationStore?
    private let now: @Sendable () -> Date
    private let hooks: Hooks

    /// Test seams that make races deterministic (both nil in the app).
    struct Hooks: Sendable {
        /// Called on the save queue right before a save is written; may block (to hold
        /// a save in progress) or throw (to simulate a full disk).
        var willPersist: (@Sendable () throws -> Void)?
        /// Called by `rekey` and `replaceContents` right before they wait for the
        /// database queue.
        var willWaitForDatabase: (@Sendable () -> Void)?

        init(willPersist: (@Sendable () throws -> Void)? = nil, willWaitForDatabase: (@Sendable () -> Void)? = nil) {
            self.willPersist = willPersist
            self.willWaitForDatabase = willWaitForDatabase
        }
    }

    private struct PersistState: Sendable {
        var key: SymmetricKey?
        var isLoaded = false
        var pending: Data?
        var isWriting = false
        var lastSaveError: String?
        /// Generation of the journal file on disk (the last save, or the file loaded).
        var generation: UInt64 = 0
        /// Epoch of the journal's current line of saves.
        var epoch = JournalStamp.newEpoch()
    }

    /// Largest database image Dojix will load or save (memory-backed).
    static let maximumImageSize = 1 << 30

    // MARK: - Init

    /// The journal at the standard location (`Configuration.dataDirectory`), not loaded yet.
    convenience init() throws {
        let dir = Configuration.dataDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        // Owner-only, also for a folder created by an older build.
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        try self.init(path: dir.appendingPathComponent(Configuration.databaseFilename).path,
                      generationStore: SaveGenerationStore())
    }

    /// A journal stored (encrypted) at `path`, not loaded yet.
    /// - Parameters:
    ///   - generationStore: where the latest save generation is recorded for rollback
    ///     protection (the app passes the Keychain; nil = not tracked).
    ///   - now: the clock used for save times (tests inject one).
    ///   - hooks: test seams (see `Hooks`).
    init(path: String, generationStore: SaveGenerationStore? = nil,
         now: @escaping @Sendable () -> Date = { Date() }, hooks: Hooks = Hooks()) throws {
        self.databasePath = path
        self.isPersistent = true
        self.generations = generationStore
        self.now = now
        self.hooks = hooks
        self.dbQueue = try DatabaseQueue(configuration: Self.makeConfiguration())
        try dbQueue.writeWithoutTransaction { db in
            // Read-only at the storage level (GRDB toggles `PRAGMA query_only` itself).
            try Self.deserialize(Self.emptyImage, into: db, readOnly: true)
        }
        let observer = CommitObserver { [weak self] db in self?.databaseDidCommit(db) }
        dbQueue.add(transactionObserver: observer, extent: .databaseLifetime)
        commitObserver = observer
    }

    /// In-memory database for tests: loaded and migrated, never written to disk.
    init(inMemory: Bool) throws {
        precondition(inMemory, "Use init() for the journal on disk")
        self.databasePath = NSTemporaryDirectory() + "dojix_test_\(UUID().uuidString).sqlite"
        self.isPersistent = false
        self.generations = nil
        self.now = { Date() }
        self.hooks = Hooks()
        self.dbQueue = try DatabaseQueue(configuration: Self.makeConfiguration())
        try Self.runMigrations(on: dbQueue)
        state.withLock { $0.isLoaded = true }
    }

    private static func makeConfiguration() -> GRDB.Configuration {
        var config = GRDB.Configuration()
        config.foreignKeysEnabled = true
        config.prepareDatabase { db in
            // Never let a database file's schema run functions with side effects.
            try db.execute(sql: "PRAGMA trusted_schema = OFF")
        }
        return config
    }

    // MARK: - State

    /// True once `load(key:)` succeeded (and until `unload()`).
    var isLoaded: Bool { state.withLock { $0.isLoaded } }

    /// The database key while the journal is loaded (used for screenshots).
    var currentKey: SymmetricKey? { state.withLock { $0.isLoaded ? $0.key : nil } }

    /// The last error from a background save, if the most recent one failed.
    var lastSaveError: String? { state.withLock { $0.lastSaveError } }

    /// Save generation of the journal file on disk.
    var savedGeneration: UInt64 { state.withLock { $0.generation } }

    // MARK: - Load / unload

    /// Decrypt the journal into memory with `key` and make it writable.
    ///
    /// - Encrypted file: decrypted in memory only.
    /// - Plaintext SQLite file (an older build, or one that quit uncleanly): read with
    ///   SQLite (so a pending `-wal` is included), then immediately replaced by the
    ///   encrypted file, and its `-wal`/`-shm` deleted.
    /// - No file: a new, empty journal.
    /// Throws `EncryptionError.decryptionFailed` if the file can't be decrypted with `key`.
    /// `previousKey`: a key from an interrupted key rotation. If the file only opens with
    /// it, the journal is loaded and immediately re-saved with `key`.
    ///
    /// Rollback protection: if the file's save generation is lower than the one recorded
    /// in the Keychain, `OlderJournalError` is thrown before anything is loaded or written,
    /// unless `allowOlderJournal` (the user confirmed): then the file is opened and the
    /// record is reset to its generation. A higher generation (the record was lost or
    /// lags behind) is accepted and the record updated by the save that follows.
    func load(key: SymmetricKey, previousKey: SymmetricKey? = nil, allowOlderJournal: Bool = false) throws {
        precondition(isPersistent, "Test databases are always loaded")
        let fileManager = FileManager.default
        DatabaseEncryption.sealStrayCopies(besides: databasePath, key: key)

        var image = Self.emptyImage
        var foundPlaintext = false
        var fileStamp: JournalStamp?
        var fileData = Data()
        let fileExists = fileManager.fileExists(atPath: databasePath)
        if fileExists {
            fileData = try Data(contentsOf: URL(fileURLWithPath: databasePath))
            if DatabaseEncryption.isPlainSQLite(fileData) {
                image = try Self.readPlaintextDatabaseFile(at: databasePath)
                foundPlaintext = true
            } else {
                do {
                    (image, fileStamp) = try DatabaseEncryption.openJournal(fileData, key: key)
                } catch {
                    guard let previousKey else { throw error }
                    (image, fileStamp) = try DatabaseEncryption.openJournal(fileData, key: previousKey)
                    Self.logger.info("Journal was still sealed with the previous key; re-sealing")
                }
                guard DatabaseEncryption.isPlainSQLite(image) else { throw DatabaseEncryption.EncryptionError.decryptionFailed }
            }
        }
        let (epoch, generation) = try checkGeneration(of: fileStamp, file: fileExists ? fileData : nil,
                                                      allowOlderJournal: allowOlderJournal)

        try dbQueue.writeWithoutTransaction { db in
            try Self.deserialize(image, into: db)
        }
        try Self.runMigrations(on: dbQueue)
        state.withLock {
            $0.key = key
            $0.isLoaded = true
            $0.pending = nil
            $0.generation = generation
            $0.epoch = epoch
        }
        // Re-save right away (new key, plaintext or older format replaced). A failure
        // here (a full disk) must not make a healthy journal unopenable: the journal
        // stays open in memory, the file on disk is left as it was, and the error is
        // kept in `lastSaveError`. The next commit tries again.
        do {
            try saveNow()
        } catch {
            state.withLock { $0.lastSaveError = error.localizedDescription }
            Self.logger.error("Could not save the journal after opening it: \(error.localizedDescription)")
            return
        }

        // Only the encrypted file is left: drop plaintext sidecars of an older build.
        for suffix in ["-wal", "-shm"] {
            try? fileManager.removeItem(atPath: databasePath + suffix)
        }
        if foundPlaintext {
            Self.logger.info("Encrypted a plaintext journal found at launch")
        }
    }

    /// The epoch and generation to continue from, after comparing the journal file with
    /// the Keychain's record of the last save. Throws `OlderJournalError` when the file
    /// is not that save (nor a later one of the same epoch) and the user hasn't allowed it.
    /// - Parameter file: the sealed file's bytes, nil when there is no file.
    private func checkGeneration(of fileStamp: JournalStamp?, file: Data?,
                                 allowOlderJournal: Bool) throws -> (epoch: Data, generation: UInt64) {
        guard let generations, let last = generations.lastSaved() else {
            // Nothing recorded (first run with rollback protection, Keychain lost or
            // reset): accept the file. Files from before save stamps (and plaintext
            // ones) count as generation 0 and start a new epoch.
            return (fileStamp?.epoch ?? JournalStamp.newEpoch(), fileStamp?.generation ?? 0)
        }
        // No journal file: a new, empty journal (new epoch) continues the count.
        guard let file else { return (JournalStamp.newEpoch(), last.stamp.generation) }
        if let fileStamp, fileStamp.epoch == last.stamp.epoch {
            // A later save of the same epoch: the record lags (a Keychain write failed).
            if fileStamp.generation > last.stamp.generation { return (fileStamp.epoch, fileStamp.generation) }
            // Exactly the last save.
            if fileStamp.generation == last.stamp.generation, last.matches(file) {
                return (fileStamp.epoch, fileStamp.generation)
            }
        }
        guard allowOlderJournal else {
            Self.logger.notice("Journal file is not the last one this Mac saved (generation \(fileStamp?.generation ?? 0), last \(last.stamp.generation))")
            throw OlderJournalError(fileStamp: fileStamp, lastSaved: last.stamp)
        }
        // Confirmed: a new epoch, so files of the line of saves being abandoned are never
        // taken as current later; the count never goes down.
        Self.logger.notice("Opening an older journal (confirmed); starting a new epoch")
        return (JournalStamp.newEpoch(), max(last.stamp.generation, fileStamp?.generation ?? 0))
    }

    /// Switch to a new database key (key rotation): from now on every save uses
    /// `newKey`, and the journal is re-saved with it before this returns.
    ///
    /// The check that the journal is open, the key swap and the save happen in one turn
    /// of the database queue, so a lock (`unload`) can't slip in between: it either runs
    /// first (then this throws `keyUnavailable` and the file keeps the old key) or after
    /// (then it saves with `newKey`). This never returns without the file on disk being
    /// sealed with `newKey`.
    func rekey(to newKey: SymmetricKey) throws {
        guard isPersistent else { return }
        hooks.willWaitForDatabase?()
        try dbQueue.writeWithoutTransaction { db in
            guard let oldKey = state.withLock({ $0.isLoaded ? $0.key : nil }) else {
                throw DatabaseEncryption.EncryptionError.keyUnavailable
            }
            let image = try Self.serialize(db)
            try writer.sync {
                state.withLock {
                    $0.pending = nil
                    $0.key = newKey
                }
                do {
                    try persist(image, key: newKey)
                } catch {
                    state.withLock {
                        $0.key = oldKey
                        $0.lastSaveError = error.localizedDescription
                    }
                    throw error
                }
                state.withLock { $0.lastSaveError = nil }
            }
        }
    }

    /// Replace the whole journal with a database image built by Dojix (restore), save it
    /// and notify observers, all in one turn of the database queue: a lock can't run in
    /// between and leave the restored rows unsaved (and writable) behind the lock screen.
    /// Throws `keyUnavailable` if the journal is closed (locked). If the swap or the save
    /// fails, the previous contents are put back (in memory; the file on disk was not
    /// replaced), so a restore reported as failed never goes live later.
    func replaceContents(with image: Data) throws {
        hooks.willWaitForDatabase?()
        try dbQueue.writeWithoutTransaction { db in
            let (isLoaded, key) = state.withLock { ($0.isLoaded, $0.key) }
            guard isLoaded else { throw DatabaseEncryption.EncryptionError.keyUnavailable }
            let previous = try Self.serialize(db)
            do {
                try Self.deserialize(image, into: db)
                if isPersistent {   // test databases are never written
                    guard let key else { throw DatabaseEncryption.EncryptionError.keyUnavailable }
                    let restored = try Self.serialize(db)
                    try writer.sync {
                        state.withLock { $0.pending = nil }
                        try persist(restored, key: key)
                        state.withLock { $0.lastSaveError = nil }
                    }
                }
            } catch {
                try? Self.deserialize(previous, into: db)
                throw error
            }
            // Tell observers (journal, dashboard) that everything changed. Only after the
            // save: this commit also schedules a background save of the restored rows.
            try db.inTransaction {
                try db.notifyChanges(in: .fullDatabase)
                return .commit
            }
        }
    }

    /// Save, then wipe the decrypted journal from memory and make the database read-only
    /// until the next `load(key:)`. If the save fails, the data is kept in memory (never
    /// discarded unsaved) and the error is thrown.
    func unload() throws {
        guard isPersistent, isLoaded else { return }
        // One turn of the database queue: save, close, wipe. A commit from another thread
        // (a background import) can't land between the save and the wipe and be lost.
        try dbQueue.writeWithoutTransaction { db in
            guard let key = state.withLock({ $0.isLoaded ? $0.key : nil }) else { return }
            let image = try Self.serialize(db)
            try writer.sync {
                state.withLock { $0.pending = nil }
                try persist(image, key: key)
                state.withLock {
                    $0.lastSaveError = nil
                    $0.isLoaded = false
                    $0.key = nil
                }
            }
            // Read-only at the storage level (GRDB toggles `PRAGMA query_only` itself).
            try Self.deserialize(Self.emptyImage, into: db, readOnly: true)
        }
    }

    /// Drop the in-memory journal without saving it (used by "Erase all local data").
    func unloadWithoutSaving() throws {
        guard isPersistent else { return }
        state.withLock {
            $0.isLoaded = false
            $0.key = nil
            $0.pending = nil
        }
        flush()
        try dbQueue.writeWithoutTransaction { db in
            // Read-only at the storage level (GRDB toggles `PRAGMA query_only` itself).
            try Self.deserialize(Self.emptyImage, into: db, readOnly: true)
        }
    }

    /// Turn a plaintext journal left by an older build into the encrypted file without
    /// loading it (used at launch while the lock screen is up, when the key is still a
    /// bare Keychain item). No-op if the file is missing or already encrypted.
    static func encryptPlaintextFileInPlace(at path: String, key: SymmetricKey) throws {
        guard isPlaintextFile(at: path) else { return }
        let image = try readPlaintextDatabaseFile(at: path)
        try DatabaseEncryption.writeSealed(image, key: key, to: path)
        for suffix in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: path + suffix)
        }
        logger.info("Encrypted a plaintext journal found at launch (before unlock)")
    }

    /// Whether the file at `path` is an unencrypted SQLite database.
    static func isPlaintextFile(at path: String) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 16) else { return false }
        return DatabaseEncryption.isPlainSQLite(head)
    }

    // MARK: - Saving

    /// Serialize the current database and write it, sealed, before returning.
    /// Throws `keyUnavailable` when the journal is closed (locked): a save that didn't
    /// happen is never reported as done.
    func saveNow() throws {
        guard isPersistent else { return }
        // Hold the database while writing so no newer commit can be overtaken by this
        // snapshot; earlier background saves run first (same serial queue).
        try dbQueue.writeWithoutTransaction { db in
            guard let key = state.withLock({ $0.isLoaded ? $0.key : nil }) else {
                throw DatabaseEncryption.EncryptionError.keyUnavailable
            }
            let image = try Self.serialize(db)
            try writer.sync {
                state.withLock { $0.pending = nil }
                try persist(image, key: key)
                state.withLock { $0.lastSaveError = nil }
            }
        }
    }

    /// Write `image` as the next save generation of the current epoch, then record that
    /// save (stamp + file hash) in the Keychain (file first: a crash in between leaves the file ahead of the record,
    /// which is accepted, never behind it). Runs on `writer` only, so generations are
    /// written in order. A Keychain that refuses the record is logged, not fatal.
    private func persist(_ image: Data, key: SymmetricKey) throws {
        let (epoch, next) = state.withLock { ($0.epoch, $0.generation &+ 1) }
        let stamp = JournalStamp(epoch: epoch, generation: next, savedAt: now())
        try hooks.willPersist?()
        let sealed = try DatabaseEncryption.writeJournal(image, key: key, stamp: stamp, to: databasePath)
        state.withLock { $0.generation = next }
        generations?.record(SaveRecord(stamp: stamp, sealedFile: sealed))
    }

    /// Wait until every scheduled background save has been written.
    func flush() {
        writer.sync {}
    }

    /// Save for app termination (synchronous). Errors are logged.
    func saveForShutdown() {
        guard isPersistent, isLoaded else { return }
        do {
            try saveNow()
        } catch {
            Self.logger.error("Failed to save the encrypted database on shutdown: \(error.localizedDescription)")
        }
    }

    /// Called on GRDB's queue after every committed transaction.
    private func databaseDidCommit(_ db: Database) {
        guard isPersistent, isLoaded else { return }
        do {
            let image = try Self.serialize(db)
            schedule(image)
        } catch {
            Self.logger.error("Could not snapshot the database: \(error.localizedDescription)")
        }
    }

    /// Coalescing background write: only the newest snapshot is written.
    private func schedule(_ image: Data) {
        let shouldStart = state.withLock { s -> Bool in
            s.pending = image
            if s.isWriting { return false }
            s.isWriting = true
            return true
        }
        if shouldStart {
            writer.async { [self] in drainPendingSaves() }
        }
    }

    private func drainPendingSaves() {
        while true {
            let next: (Data, SymmetricKey)? = state.withLock { s in
                guard let data = s.pending, let key = s.key, s.isLoaded else {
                    s.pending = nil
                    s.isWriting = false
                    return nil
                }
                s.pending = nil
                return (data, key)
            }
            guard let (image, key) = next else { return }
            do {
                try persist(image, key: key)
                state.withLock { $0.lastSaveError = nil }
            } catch {
                state.withLock { $0.lastSaveError = error.localizedDescription }
                Self.logger.error("Background save failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Files on disk

    /// Delete the encrypted journal and every file that belongs to it (legacy plaintext
    /// copies, `-wal`/`-shm`, interrupted saves). Used by "Erase all local data".
    func deleteFilesOnDisk() throws {
        guard isPersistent else { return }
        flush()
        let fileManager = FileManager.default
        for url in try DatabaseEncryption.strayFiles(besides: databasePath) {
            try fileManager.removeItem(at: url)
        }
        if fileManager.fileExists(atPath: databasePath) {
            try fileManager.removeItem(atPath: databasePath)
        }
    }

    // MARK: - Serialization

    /// An empty SQLite image (one page), used to reset the in-memory database.
    static let emptyImage: Data = {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open(":memory:", &db) == SQLITE_OK else { return Data() }
        var size: sqlite3_int64 = 0
        guard let bytes = sqlite3_serialize(db, "main", &size, 0) else { return Data() }
        defer { sqlite3_free(bytes) }
        return Data(bytes: bytes, count: Int(size))
    }()

    /// The whole database as a SQLite file image.
    static func serialize(_ db: Database) throws -> Data {
        var size: sqlite3_int64 = 0
        guard let bytes = sqlite3_serialize(db.sqliteConnection, "main", &size, 0) else {
            throw DatabaseError(resultCode: .SQLITE_NOMEM, message: "Could not serialize the database")
        }
        defer { sqlite3_free(bytes) }
        guard size >= 0, size <= maximumImageSize else {
            throw DatabaseError(resultCode: .SQLITE_TOOBIG, message: "Database too large")
        }
        return Data(bytes: bytes, count: Int(size))
    }

    /// Replace the contents of `db` with a SQLite file image (kept in memory only).
    /// `readOnly` opens the image without allowing changes (used to inspect backups).
    static func deserialize(_ image: Data, into db: Database, readOnly: Bool = false) throws {
        var bytes = [UInt8](image)
        guard bytes.count >= 100, bytes.count <= maximumImageSize,
              Data(bytes[0..<16]) == DatabaseEncryption.sqliteMagic else {
            throw DatabaseError(resultCode: .SQLITE_NOTADB, message: "Not a SQLite database")
        }
        // A file saved in WAL mode can't be opened from memory: mark it as a rollback-journal
        // database (file format bytes 18 and 19; the pages themselves are identical).
        if bytes[18] == 2 { bytes[18] = 1 }
        if bytes[19] == 2 { bytes[19] = 1 }
        let count = bytes.count
        guard let buffer = sqlite3_malloc64(UInt64(count)) else {
            throw DatabaseError(resultCode: .SQLITE_NOMEM, message: "Out of memory")
        }
        bytes.withUnsafeBytes { raw in
            // Safe: `bytes` is non-empty (checked above), so baseAddress is non-nil.
            buffer.copyMemory(from: raw.baseAddress!, byteCount: count)
        }
        var flags = UInt32(SQLITE_DESERIALIZE_FREEONCLOSE | SQLITE_DESERIALIZE_RESIZEABLE)
        if readOnly { flags |= UInt32(SQLITE_DESERIALIZE_READONLY) }
        // SQLite takes ownership of `buffer` (FREEONCLOSE), also when it fails.
        let rc = sqlite3_deserialize(db.sqliteConnection, "main", buffer.assumingMemoryBound(to: UInt8.self),
                                     sqlite3_int64(count), sqlite3_int64(count), flags)
        guard rc == SQLITE_OK else {
            throw DatabaseError(resultCode: ResultCode(rawValue: rc), message: "Could not load the database image")
        }
        db.clearSchemaCache()
    }

    /// Read a plaintext SQLite file (including any pending `-wal`) into an image.
    static func readPlaintextDatabaseFile(at path: String) throws -> Data {
        let file = try DatabaseQueue(path: path, configuration: makeConfiguration())
        defer { try? file.close() }
        let memory = try DatabaseQueue(configuration: makeConfiguration())
        try file.backup(to: memory)
        return try memory.writeWithoutTransaction { db in try serialize(db) }
    }
}

// MARK: - Commit observer

/// Calls back after every committed transaction (on the database queue).
private final class CommitObserver: TransactionObserver {
    private let onCommit: (Database) -> Void

    init(onCommit: @escaping (Database) -> Void) {
        self.onCommit = onCommit
    }

    func observes(eventsOfKind eventKind: DatabaseEventKind) -> Bool { true }
    func databaseDidChange(with event: DatabaseEvent) {}
    func databaseDidCommit(_ db: Database) { onCommit(db) }
    func databaseDidRollback(_ db: Database) {}
}
