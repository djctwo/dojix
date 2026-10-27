import Foundation
import os

/// Watches an MT5 files folder for StrategyAnalytics CSV exports.
///
/// - Scans once at start (files written while Dojix was closed are picked up).
/// - Reacts to folder changes (new or renamed files) via DispatchSource.
/// - Polls every `pollInterval` seconds, because MT5 rewrites the same-day file
///   in place, which does not trigger a folder event.
/// - Skips files whose size and modification date haven't changed since the last
///   import attempt. Trades are de-duplicated by ticket anyway.
/// The folder is only ever read.
final class FileWatcher: Sendable {
    private static let logger = Logger(subsystem: "com.dojix", category: "FileWatcher")

    let watchPath: String
    private let queue = DispatchQueue(label: "com.dojix.filewatcher", qos: .utility)
    private let source: DispatchSourceFileSystemObject?
    private let timer: DispatchSourceTimer
    private let ledger = Ledger()
    private let callback: @Sendable (String) -> Void

    /// Size + modification date of each file already handed to the importer.
    /// Only touched on `queue`.
    private final class Ledger: @unchecked Sendable {
        var seen: [String: String] = [:]
    }

    /// - Parameters:
    ///   - path: folder to watch
    ///   - pollInterval: seconds between rescans (catches in-place rewrites)
    ///   - onChange: called with the full path of each new or changed SA CSV
    init(path: String, pollInterval: TimeInterval = 60, onChange: @escaping @Sendable (String) -> Void) {
        self.watchPath = path
        self.callback = onChange
        self.timer = DispatchSource.makeTimerSource(queue: queue)

        let fd = open(path, O_EVTONLY)
        if fd >= 0 {
            let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: queue)
            src.setCancelHandler { close(fd) }
            self.source = src
        } else {
            Self.logger.warning("Cannot watch folder (not found): \(path)")
            self.source = nil
        }

        source?.setEventHandler { [weak self] in self?.scan() }
        timer.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        timer.setEventHandler { [weak self] in self?.scan() }
    }

    /// Start watching (runs an initial scan right away)
    func start() {
        source?.resume()
        timer.resume()
        queue.async { [weak self] in self?.scan() }
        Self.logger.info("File watcher started for: \(self.watchPath)")
    }

    /// Stop watching
    func stop() {
        source?.cancel()
        timer.cancel()
        Self.logger.info("File watcher stopped")
    }

    /// Hand every new or changed SA CSV in the folder to the callback. Runs on `queue`.
    private func scan() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: watchPath) else { return }
        for file in files where file.hasPrefix(Configuration.saCSVPattern) && file.lowercased().hasSuffix(".csv") {
            let fullPath = (watchPath as NSString).appendingPathComponent(file)
            guard let attrs = try? fm.attributesOfItem(atPath: fullPath),
                  (attrs[.type] as? FileAttributeType) == .typeRegular else { continue }
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? -1
            let modified = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let fingerprint = "\(size)|\(modified)"
            if ledger.seen[fullPath] == fingerprint { continue }
            ledger.seen[fullPath] = fingerprint
            callback(fullPath)
        }
    }
}
