import XCTest
@testable import Dojix

/// Regressions for hostile imports and exports (F5–F8). These use only APIs that also
/// exist before the fix, so they can be run against the old code to show the failure.
final class HostileInputRegressionTests: XCTestCase {
    private func trade(ticket: Int64, lots: Double = 0.1, durationMin: Int = 60, symbol: String = "EURUSD") -> Trade {
        let close = Date(timeIntervalSince1970: 1_767_225_600)
        return Trade(
            id: nil, ticket: ticket, symbol: symbol, direction: .buy,
            lots: lots, openTime: close.addingTimeInterval(-3600), closeTime: close, durationMin: durationMin,
            openPrice: 1.1, closePrice: 1.101, sl: 1.09, tp: 1.12, netProfit: 10,
            maePips: 3, mfePips: 8, rMultiple: 1, session: .london, dayOfWeek: "Thu", hour: 10,
            rangeSize: 20, sweepDepth: 4, usedFVG: false, volRegime: .med,
            hitBreakeven: false, scaledIn: false, magic: 0, comment: "Sample (fictional)",
            timeToMFEMin: 10, slDistPips: 10, slippagePips: 0,
            postClose15m: 0, postClose30m: 0, biasAtEntry: .neutral, importedAt: close
        )
    }

    // F5: imported lot sizes are held to a minimum (zero = unknown size is kept)
    func testSanitizerEnforcesMinimumLotSize() {
        XCTAssertEqual(trade(ticket: 1, lots: 1e-15).sanitizedForStorage().lots, 0.00001)
        XCTAssertEqual(trade(ticket: 2, lots: -1e-9).sanitizedForStorage().lots, 0.00001)
        XCTAssertEqual(trade(ticket: 3, lots: 0).sanitizedForStorage().lots, 0)
        XCTAssertEqual(trade(ticket: 4, lots: 0.01).sanitizedForStorage().lots, 0.01)
        XCTAssertEqual(trade(ticket: 5, lots: 5e9).sanitizedForStorage().lots, 1_000_000)
    }

    // F6: summing stored durations must not trap on overflow
    func testDurationAverageDoesNotOverflow() {
        let trades = [trade(ticket: 1, durationMin: Int.max - 10), trade(ticket: 2, durationMin: Int.max - 10)]
        let metrics = MetricsCalculator.calculate(from: trades)
        XCTAssertGreaterThan(metrics.averageDuration, 0)
    }

    // F7: a bare CR (or LF) can't split a row and smuggle in an unchecked first cell
    func testCSVFieldWithBareCRIsNeutralised() {
        let field = CSVExporter.sanitizeCSVField("EURUSD\r=HYPERLINK(\"http://x\",\"y\")")
        XCTAssertFalse(field.contains("\r"))
        XCTAssertFalse(field.contains("\n"))
        XCTAssertEqual(CSVExporter.sanitizeCSVField("=1+2"), "'=1+2")
        XCTAssertEqual(CSVExporter.sanitizeCSVField("-12.50"), "-12.50")
        XCTAssertEqual(CSVExporter.sanitizeCSVField("a,b"), "\"a,b\"")
        // A field that starts with a control character is checked after it is removed
        XCTAssertEqual(CSVExporter.sanitizeCSVField("\t=cmd"), "'=cmd")
    }

    // F8: a screenshot named ".." or "." must never delete anything outside the trade's file
    func testDotDotScreenshotNameDeletesNothing() throws {
        let manager = ScreenshotManager.shared
        let victim = manager.screenshotDir(for: 987_654_322)
        try FileManager.default.createDirectory(at: victim, withIntermediateDirectories: true)
        let kept = victim.appendingPathComponent("\(UUID().uuidString).jpg")
        try Data([0xFF, 0xD8, 0xFF]).write(to: kept)
        try FileManager.default.createDirectory(at: manager.screenshotDir(for: 987_654_321), withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: victim)
            try? FileManager.default.removeItem(at: manager.screenshotDir(for: 987_654_321))
        }

        for name in ["..", ".", "../987654322", ".hidden.jpg", ""] {
            try? manager.deleteImage(filename: name, for: 987_654_321)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path), "another trade's screenshot was deleted")
        XCTAssertTrue(FileManager.default.fileExists(atPath: manager.screenshotDir(for: 987_654_321).path))

        // No name may resolve to anything but a file directly inside the trade's folder
        let tradeDir = Self.realPath(manager.screenshotDir(for: 987_654_321).path)
        for name in ["..", "."] {
            let url: URL? = manager.imageURL(filename: name, for: 987_654_321)
            if let url {
                let resolved = Self.realPath(url.path)
                XCTAssertEqual((resolved as NSString).deletingLastPathComponent, tradeDir,
                               "\(name) resolves outside the trade's folder")
            }
        }
    }

    // F8: only names the app creates (<UUID>.jpg) can be deleted through a screenshot entry
    func testOnlyAppCreatedScreenshotNamesCanBeDeleted() throws {
        let manager = ScreenshotManager.shared
        let dir = manager.screenshotDir(for: 987_654_323)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let other = dir.appendingPathComponent("notes.txt")
        let hidden = dir.appendingPathComponent(".hidden.jpg")
        try Data("keep".utf8).write(to: other)
        try Data("keep".utf8).write(to: hidden)

        try? manager.deleteImage(filename: "notes.txt", for: 987_654_323)
        try? manager.deleteImage(filename: ".hidden.jpg", for: 987_654_323)

        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path), "a file Dojix didn't create was deleted")
        XCTAssertTrue(FileManager.default.fileExists(atPath: hidden.path), "a hidden file was deleted")
    }

    /// The canonical path of an existing file or folder (symlinks and ".." resolved).
    private static func realPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
