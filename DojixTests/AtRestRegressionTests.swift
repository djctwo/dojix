import XCTest
@testable import Dojix

/// F1/F3/F4: while Dojix runs (here: the test host app, opened on its scratch data
/// folder), the journal on disk must not be a readable SQLite file. Uses only APIs that
/// existed before the fix, so it shows the old behaviour failing.
final class AtRestRegressionTests: XCTestCase {
    func testJournalOnDiskIsNotPlaintextWhileTheAppRuns() throws {
        // Touch the app-wide state so the host app has opened its journal
        _ = try AppState.shared.tradeRepository.count()

        let dir = Configuration.dataDirectory
        let path = dir.appendingPathComponent(Configuration.databaseFilename).path
        XCTAssertTrue(FileManager.default.fileExists(atPath: path), "the journal file exists")
        let head = try XCTUnwrap(FileHandle(forReadingAtPath: path)?.readData(ofLength: 16))
        XCTAssertNotEqual(head, Data("SQLite format 3\u{0}".utf8), "the journal on disk is readable SQLite")
        XCTAssertFalse(FileManager.default.fileExists(atPath: path + "-wal"), "a plaintext write-ahead log is on disk")
    }
}
