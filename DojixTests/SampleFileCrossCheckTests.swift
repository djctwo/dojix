import XCTest
@testable import Dojix

/// The fictional sample in samples/sample-mt4.csv, imported end to end, must give the
/// same headline numbers as a hand calculation.
///
/// Profit + commission + swap per trade: 48, -32, 76, -21, 24
/// Net P&L = 95; wins 3 (gross 148), losses 2 (gross 53)
/// Win rate = 60%; profit factor = 148 / 53 = 2.792; expectancy = 95 / 5 = 19.00
final class SampleFileCrossCheckTests: XCTestCase {

    private let csv = """
    Ticket,Open Time,Close Time,Type,Size,Item,Price,S/L,T/P,Close Price,Profit,Commission,Swap
    5001,2026.03.02 08:15:00,2026.03.02 09:40:00,BUY,0.10,EURUSD,1.08000,1.07800,1.08500,1.08500,50.00,-2.00,0.00
    5002,2026.03.03 13:05:00,2026.03.03 14:10:00,SELL,0.20,GBPUSD,1.27000,1.27200,1.26500,1.27150,-30.00,-2.00,0.00
    5003,2026.03.04 02:30:00,2026.03.04 05:00:00,BUY,0.10,USDJPY,150.000,149.700,150.800,150.800,80.00,-3.00,-1.00
    5004,2026.03.05 15:45:00,2026.03.05 16:20:00,SELL,0.10,AUDUSD,0.66000,0.66200,0.65500,0.66200,-20.00,-1.00,0.00
    5005,2026.03.06 09:00:00,2026.03.06 10:30:00,BUY,0.05,EURUSD,1.08200,1.08000,1.08800,1.08700,25.00,-1.00,0.00
    """

    func testMT4SampleHeadlineStatsMatchHandCalculation() throws {
        let path = NSTemporaryDirectory() + "dojix_sample_mt4_\(UUID().uuidString).csv"
        try csv.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let detection = try GenericCSVParser.detect(fileAt: path)
        XCTAssertEqual(detection.platform, .mt4)
        let trades = try GenericCSVParser.parse(fileAt: path, mapping: try XCTUnwrap(detection.mapping))

        let repo = TradeRepository(database: try DatabaseManager(inMemory: true))
        XCTAssertEqual(try repo.bulkInsert(trades), 5)
        let m = MetricsCalculator.calculate(from: try repo.fetchAll())

        XCTAssertEqual(m.totalTrades, 5)
        XCTAssertEqual(m.totalProfit, 95, accuracy: 0.001)
        XCTAssertEqual(m.winRate, 60, accuracy: 0.001)
        XCTAssertEqual(m.profitFactor, 148.0 / 53.0, accuracy: 0.001)
        XCTAssertEqual(m.expectancy, 19, accuracy: 0.001)
    }

    func testBuiltInSampleTradesHeadlineStats() {
        // Hand calculation over the 30 template profits in DemoDataGenerator:
        // gross profit 1,450 (20 wins), gross loss 605 (10 losses)
        let m = MetricsCalculator.calculate(from: DemoDataGenerator.generateTrades())
        XCTAssertEqual(m.totalProfit, 845, accuracy: 0.001)
        XCTAssertEqual(m.winRate, 200.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(m.profitFactor, 1450.0 / 605.0, accuracy: 0.001)
        XCTAssertEqual(m.expectancy, 845.0 / 30.0, accuracy: 0.001)
    }
}
