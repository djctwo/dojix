import Darwin
import Foundation
import os

/// Writes files that hold journal data (the encrypted journal, screenshots, backups, CSV
/// and PDF exports) so that only the current macOS user can read them, never other
/// accounts on the same Mac, whatever folder they are saved in.
enum OwnerOnlyFile {
    private static let logger = Logger(subsystem: "com.dojix", category: "OwnerOnlyFile")

    /// Atomic, durable replace, safe in shared folders:
    /// 1. create a temp file with a random name next to `path` with
    ///    `O_CREAT | O_EXCL | O_NOFOLLOW`, mode 0600 (never an existing file or symlink),
    /// 2. write, `fchmod` 0600 and force the data to stable storage (`F_FULLFSYNC`; plain
    ///    `fsync` on macOS can leave it in the drive's cache) through that same descriptor
    ///    (never reopened by path),
    /// 3. `rename` it over `path` (a symlink at `path` is replaced, not followed),
    /// 4. force the folder to disk, so the rename itself survives a power loss.
    /// When this returns, the new file is on disk under its name: the caller may record
    /// that (the save generation) or drop an old key.
    /// The temp file is removed on any failure.
    /// - Parameters:
    ///   - failure: the error thrown when the temp file can't be created or renamed.
    ///   - sync: how data and folder are flushed (tests wrap `.system` to record the order).
    static func write(_ data: Data, to path: String,
                      failure: @autoclosure () -> Error = CocoaError(.fileWriteUnknown),
                      sync: FileSync = .system) throws {
        let destination = URL(fileURLWithPath: path)
        let folder = destination.deletingLastPathComponent().path
        // "<name>.<random>.saving": recognised (and cleaned up) as an interrupted save.
        let tempPath = destination.deletingLastPathComponent()
            .appendingPathComponent("\(destination.lastPathComponent).\(UUID().uuidString).saving").path
        let descriptor = open(tempPath, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw failure() }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: data)
            guard fchmod(descriptor, 0o600) == 0 else { throw failure() }
            try sync.syncFile(descriptor)
            try handle.close()
        } catch {
            try? handle.close()
            unlink(tempPath)
            throw error
        }
        guard rename(tempPath, path) == 0 else {
            unlink(tempPath)
            throw failure()
        }
        sync.syncDirectory(folder)
    }

    /// How a written file (and the folder holding its new name) is forced to disk.
    /// Tests wrap `.system` to record the order of the steps.
    struct FileSync: Sendable {
        /// Flush a file's data to stable storage. Throws if it can't be flushed at all.
        var syncFile: @Sendable (_ descriptor: Int32) throws -> Void
        /// Flush a folder, so a rename in it survives a power loss. Best effort: the
        /// rename has already happened, so a failure is logged, not thrown.
        var syncDirectory: @Sendable (_ path: String) -> Void

        /// `F_FULLFSYNC`, falling back to `fsync` where a file system doesn't support it.
        static let system = FileSync(
            syncFile: { descriptor in
                if fcntl(descriptor, F_FULLFSYNC) == 0 { return }
                guard fsync(descriptor) == 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
            },
            syncDirectory: { path in
                let descriptor = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
                guard descriptor >= 0 else {
                    OwnerOnlyFile.logger.error("Could not open a folder to flush it (errno \(errno))")
                    return
                }
                defer { close(descriptor) }
                if fcntl(descriptor, F_FULLFSYNC) != 0, fsync(descriptor) != 0 {
                    OwnerOnlyFile.logger.error("Could not flush a folder (errno \(errno))")
                }
            })
    }

    /// `write(_:to:)` for a file URL.
    static func write(_ data: Data, to url: URL) throws {
        try write(data, to: url.path)
    }
}
