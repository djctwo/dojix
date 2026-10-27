import Darwin
import Foundation
import os

/// One running Dojix per data folder. The journal lives in memory and every save
/// rewrites the whole file, so two running copies (an unzipped copy next to the one in
/// Applications, `open -n`) would overwrite each other's saves. The first copy holds an
/// exclusive `flock` on `Dojix.lock` in the data folder for as long as it runs (macOS
/// releases it when the process ends, also after a crash); a second copy can't get it
/// and opens nothing.
final class InstanceLock: Sendable {
    static let filename = "Dojix.lock"
    private static let logger = Logger(subsystem: "com.dojix", category: "InstanceLock")

    enum Result {
        /// This copy is the only one using the folder (keep the lock for the process' life).
        case acquired(InstanceLock)
        /// Another running copy holds the folder.
        case heldByAnotherCopy
        /// The lock file couldn't be opened (an unwritable folder): not a second copy, so
        /// opening goes ahead.
        case unavailable
    }

    private let descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }

    /// Try to become the copy that uses `directory`.
    static func acquire(in directory: URL) -> Result {
        let path = directory.appendingPathComponent(filename).path
        let descriptor = open(path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else {
            logger.error("Could not open the single-instance lock (errno \(errno))")
            return .unavailable
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let reason = errno
            close(descriptor)
            if reason == EWOULDBLOCK { return .heldByAnotherCopy }
            logger.error("Could not take the single-instance lock (errno \(reason))")
            return .unavailable
        }
        return .acquired(InstanceLock(descriptor: descriptor))
    }
}
