import XCTest
@testable import Dojix

/// Files without broker ticket numbers must be safe to import twice.
final class ReimportDedupeTests: XCTestCase {

    private var tempFiles: [String] = []

    override func tearDown() {
        for path in tempFiles { try? FileManager.default.removeItem(atPath: path) }
        tempFiles = []
        super.tearDown()
    }

    private func write(_ content: String, _ name: String) -> String {
        let path = NSTemporaryDirectory() + "dojix_dedupe_\(name)_\(UUID().uuidString).csv"
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
        tempFiles.append(path)
        return path
    }

    private let ticketlessMapping = GenericCSVParser.ColumnMapping(
        platform: .generic, ticket: nil, symbol: 0, direction: 1, lots: 2, openTime: 3,
        closeTime: 4, openPrice: 5, closePrice: 6, sl: nil, tp: nil, profit: 7,
        commission: nil, swap: nil, maePips: nil, mfePips: nil, pips: nil,
        dateFormat: "yyyy-MM-dd HH:mm:ss"
    )

    private let csv = """
    Symbol,Side,Qty,Open,Close,OpenPrice,ClosePrice,Profit
    EURUSD,BUY,0.10,2026-02-02 09:00:00,2026-02-02 10:00:00,1.08000,1.08200,20.00
    GBPUSD,SELL,0.20,2026-02-03 13:00:00,2026-02-03 14:30:00,1.27000,1.27100,-20.00
    GBPUSD,SELL,0.20,2026-02-03 13:00:00,2026-02-03 14:30:00,1.27000,1.27100,-20.00
    """

    func testReimportingTicketlessFileAddsNothing() throws {
        let path = write(csv, "ticketless")
        let repo = TradeRepository(database: try DatabaseManager(inMemory: true))

        let first = try GenericCSVParser.parse(fileAt: path, mapping: ticketlessMapping)
        XCTAssertEqual(try repo.bulkInsert(first), 3, "two identical rows in one file are two trades")

        let second = try GenericCSVParser.parse(fileAt: path, mapping: ticketlessMapping)
        XCTAssertEqual(try repo.bulkInsert(second), 0, "re-import must not duplicate")
        XCTAssertEqual(try repo.count(), 3)
    }

    func testPerExportTradeNumbersDoNotHideNewTrades() throws {
        // NinjaTrader / TradingView restart "Trade #" at 1 in every export
        let header = "Trade #,Instrument,Market position,Quantity,Entry price,Exit price,Entry time,Exit time,Profit,Commission\n"
        let exportA = header + "1,EURUSD,Long,1,1.0800,1.0820,02/02/2026 09:00:00,02/02/2026 10:00:00,200,0\n"
        let exportB = header + "1,GBPUSD,Short,1,1.2700,1.2690,02/09/2026 09:00:00,02/09/2026 10:00:00,100,0\n"
        let pathA = write(exportA, "ninja_a")
        let pathB = write(exportB, "ninja_b")
        let repo = TradeRepository(database: try DatabaseManager(inMemory: true))

        for path in [pathA, pathB] {
            let detection = try GenericCSVParser.detect(fileAt: path)
            let mapping = try XCTUnwrap(detection.mapping, "format should be detected")
            try repo.bulkInsert(try GenericCSVParser.parse(fileAt: path, mapping: mapping))
        }
        XCTAssertEqual(try repo.count(), 2, "the second export's trade #1 is a different trade")
    }
}

/// Streaming prices must reach the on-screen quote list.
@MainActor
final class StreamingQuotesTests: XCTestCase {
    func testStreamedPricesAreDisplayed() {
        let vm = PulseViewModel()
        // Simulate an active streaming source receiving a price
        vm.liveDataManager.setActiveSourceForTesting(.oandaStreaming)
        vm.liveDataManager.record(PriceUpdate(symbol: "EUR_USD", bid: 1.1000, ask: 1.1002))
        let pairs = vm.displayQuotes.map(\.symbol)
        XCTAssertTrue(vm.quotes.isEmpty, "the REST list the view used to render stays empty while streaming")
        XCTAssertTrue(pairs.contains("EUR/USD"), "streamed EUR/USD should be shown, got \(pairs)")
        XCTAssertEqual(vm.displayQuotes.first { $0.symbol == "EUR/USD" }?.close ?? 0, 1.1001, accuracy: 1e-9)
    }
}
