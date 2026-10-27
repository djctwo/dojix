import XCTest
@testable import Dojix

/// The MT5 watcher must pick up files already present at start and same-day
/// files that MT5 rewrites in place, without re-importing unchanged files.
final class FileWatcherTests: XCTestCase {

    private final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var paths: [String] = []
        func add(_ p: String) { lock.lock(); paths.append(p); lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return paths.count }
    }

    func testInitialScanInPlaceRewriteAndNoRepeat() throws {
        let dir = NSTemporaryDirectory() + "dojix_watch_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let file = (dir as NSString).appendingPathComponent("StrategyAnalytics_Results_20260105.csv")
        try "first".write(toFile: file, atomically: false, encoding: .utf8)
        try "ignored".write(toFile: (dir as NSString).appendingPathComponent("notes.csv"), atomically: false, encoding: .utf8)

        let calls = Calls()
        let watcher = FileWatcher(path: dir, pollInterval: 0.3) { calls.add($0) }
        watcher.start()
        defer { watcher.stop() }

        // Present before start -> picked up by the initial scan
        XCTAssertTrue(waitUntil { calls.count == 1 }, "initial scan should import the existing file")

        // Unchanged -> not handed over again
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertEqual(calls.count, 1)

        // Rewritten in place (no folder event) -> picked up by the poll
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: file))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(" plus more rows".utf8))
        try handle.close()
        XCTAssertTrue(waitUntil { calls.count == 2 }, "in-place rewrite should be re-imported")
    }

    func testDefaultFoldersIncludeCommonFiles() {
        // With no saved folder and no override, both standard MT5 folders are watched
        guard ProcessInfo.processInfo.environment["DOJIX_MT5_DIR"] == nil,
              UserDefaults.standard.string(forKey: Configuration.mt5FolderDefaultsKey) == nil else {
            return
        }
        XCTAssertTrue(Configuration.mt5WatchFolders.contains { $0.hasSuffix("Terminal/Common/Files") })
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }
}
