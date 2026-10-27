import XCTest
@testable import Dojix

/// Malformed, hostile and oversized import files must never crash, hang,
/// or put non-finite / out-of-range values into the database.
final class ImportHardeningTests: XCTestCase {

    private var tempFiles: [String] = []

    override func tearDown() {
        for path in tempFiles { try? FileManager.default.removeItem(atPath: path) }
        tempFiles = []
        super.tearDown()
    }

    private func write(_ content: String, _ name: String) -> String {
        let path = NSTemporaryDirectory() + "dojix_hardening_\(name)_\(UUID().uuidString).csv"
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
        tempFiles.append(path)
        return path
    }

    private static let saHeader = "Ticket,Symbol,Direction,Lots,OpenTime,CloseTime,DurationMin,OpenPrice,ClosePrice,SL,TP,NetProfit,MAE_Pips,MFE_Pips,RMultiple,Session,DayOfWeek,Hour,RangeSize,SweepDepth,UsedFVG,VolRegime,HitBreakeven,ScaledIn,Magic,Comment,TimeToMFE_Min,SLDist_Pips,Slippage_Pips,PostClose15m,PostClose30m,BiasAtEntry"

    // MARK: - Hostile SA rows

    func testHostileSARowsAreSanitizedBeforeStorage() throws {
        let longSymbol = String(repeating: "X", count: 10_000)
        let rows = [
            // NaN / infinity in every numeric column, impossible hour and day
            "1,EURUSD,BUY,nan,2026.01.05 09:00:00,2026.01.05 10:00:00,-50,1.1,1.2,0,0,inf,nan,inf,-inf,LONDON,Funday,99,nan,inf,NO,MED,NO,NO,1,c,-9,nan,inf,nan,-inf,WITH",
            // Absurd magnitudes and a control-character-laden, oversized symbol
            "2,\(longSymbol)\u{0007},SELL,1e308,2026.01.05 09:00:00,2026.01.04 10:00:00,999999999,1e300,0,0,0,1e300,1e300,1e300,1e300,ASIAN,Mon,-3,1,1,NO,LOW,NO,NO,1,\"=HYPERLINK(\"\"x\"\")\",1,1,1,1,1,AGAINST",
            // Unbalanced quote, too few columns, non-numeric ticket — must be skipped, not crash
            "3,\"GBPUSD,BUY,0.1",
            "abc,GBPUSD,BUY,0.1,2026.01.05 09:00:00,2026.01.05 10:00:00,60,1,1,0,0,10,1,1,1,LONDON,Mon,9,1,1,NO,MED,NO,NO,1,,1,1,1,1,1,WITH",
            "99999999999999999999999,GBPUSD,BUY,0.1,2026.01.05 09:00:00,2026.01.05 10:00:00,60,1,1,0,0,10,1,1,1,LONDON,Mon,9,1,1,NO,MED,NO,NO,1,,1,1,1,1,1,WITH",
        ]
        let path = write(Self.saHeader + "\n" + rows.joined(separator: "\n") + "\n", "sa_hostile")

        let parsed = try CSVParser.parse(fileAt: path)
        XCTAssertEqual(parsed.count, 2, "Only the two structurally valid rows should parse")

        let repo = TradeRepository(database: try DatabaseManager(inMemory: true))
        XCTAssertEqual(try repo.bulkInsert(parsed), 2)
        let stored = try repo.fetchAll()
        XCTAssertEqual(stored.count, 2)

        for t in stored {
            for value in [t.lots, t.maePips, t.mfePips, t.rMultiple, t.rangeSize, t.sweepDepth,
                          t.slDistPips, t.slippagePips, t.postClose15m, t.postClose30m] {
                XCTAssertTrue(value.isFinite, "non-finite value stored for ticket \(t.ticket)")
            }
            XCTAssertFalse(t.netProfit.isNaN)
            XCTAssertTrue((0...23).contains(t.hour))
            XCTAssertTrue(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].contains(t.dayOfWeek))
            XCTAssertGreaterThanOrEqual(t.durationMin, 0)
            XCTAssertLessThanOrEqual(t.symbol.count, 32)
            XCTAssertFalse(t.symbol.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) })
            XCTAssertGreaterThanOrEqual(t.closeTime, t.openTime)
        }

        // Analytics over sanitized data must stay finite
        let metrics = MetricsCalculator.calculate(from: stored)
        XCTAssertTrue(metrics.winRate.isFinite)
        XCTAssertTrue(metrics.expectancy.isFinite)
        _ = MetricsCalculator.edgeByHour(from: stored)
        _ = MetricsCalculator.allEdgeConditions(from: stored, tradingDays: 1)
    }

    // MARK: - Generic CSV division by zero

    func testGenericZeroLotsWithStopLossDoesNotStoreInfiniteR() throws {
        let csv = "Ticket,Open Time,Close Time,Type,Size,Item,Price,S/L,T/P,Profit,Commission,Swap\n" +
                  "500,2024.01.15 08:30:00,2024.01.15 09:45:00,BUY,0,GBPUSD,1.25000,1.24800,1.25500,25.00,0,0\n"
        let path = write(csv, "generic_zero_lots")
        let detection = try GenericCSVParser.detect(fileAt: path)
        let mapping = try XCTUnwrap(detection.mapping)
        let trades = try GenericCSVParser.parse(fileAt: path, mapping: mapping)
        XCTAssertEqual(trades.count, 1)

        let repo = TradeRepository(database: try DatabaseManager(inMemory: true))
        try repo.bulkInsert(trades)
        let stored = try XCTUnwrap(try repo.fetchAll().first)
        XCTAssertTrue(stored.rMultiple.isFinite)
    }

    // MARK: - Garbage and oversized files

    func testBinaryGarbageDoesNotCrash() throws {
        var bytes = [UInt8](repeating: 0, count: 64 * 1024)
        for i in bytes.indices { bytes[i] = UInt8((i * 7919) % 256) }
        let path = NSTemporaryDirectory() + "dojix_hardening_garbage_\(UUID().uuidString).csv"
        FileManager.default.createFile(atPath: path, contents: Data(bytes))
        tempFiles.append(path)

        XCTAssertThrowsError(try CSVParser.parse(fileAt: path))
        _ = try? GenericCSVParser.detect(fileAt: path)
    }

    func testOversizedFileIsRejectedWithoutReading() throws {
        let path = NSTemporaryDirectory() + "dojix_hardening_big_\(UUID().uuidString).csv"
        FileManager.default.createFile(atPath: path, contents: nil)
        tempFiles.append(path)
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        try handle.truncate(atOffset: 51 * 1024 * 1024) // sparse file, no real disk use
        try handle.close()

        XCTAssertThrowsError(try CSVParser.parse(fileAt: path)) { error in
            guard case CSVParser.ParseError.fileTooLarge = error else {
                return XCTFail("expected fileTooLarge, got \(error)")
            }
        }
        XCTAssertThrowsError(try GenericCSVParser.detect(fileAt: path))
    }

    // MARK: - No hang on large-but-allowed input

    func testLargeGenericFileParsesInReasonableTime() throws {
        var lines = ["Ticket,Open Time,Close Time,Type,Size,Item,Price,S/L,T/P,Profit,Commission,Swap"]
        lines.reserveCapacity(50_001)
        for i in 0..<50_000 {
            lines.append("\(i + 1),2024.01.15 08:30:00,2024.01.15 09:45:00,BUY,0.10,GBPUSD,1.25000,1.24800,1.25500,25.00,-2.00,0.00")
        }
        let path = write(lines.joined(separator: "\n"), "generic_large")
        let detection = try GenericCSVParser.detect(fileAt: path)
        let mapping = try XCTUnwrap(detection.mapping)

        let start = Date()
        let trades = try GenericCSVParser.parse(fileAt: path, mapping: mapping)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(trades.count, 50_000)
        XCTAssertLessThan(elapsed, 20, "50k-row import took \(elapsed)s")
        print("50k generic rows parsed in \(elapsed)s")
    }

    func testSingleHugeLineDoesNotHang() throws {
        // ~5 MB on one line with a million empty columns
        let line = String(repeating: ",", count: 5_000_000)
        let path = write(Self.saHeader + "\n1" + line + "\n", "huge_line")
        let start = Date()
        _ = try? CSVParser.parse(fileAt: path)
        _ = try? GenericCSVParser.detect(fileAt: path)
        XCTAssertLessThan(Date().timeIntervalSince(start), 30)
    }
}
