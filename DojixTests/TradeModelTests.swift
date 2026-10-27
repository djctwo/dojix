import XCTest
@testable import Dojix

final class TradeModelTests: XCTestCase {

    // MARK: - Test Helpers

    private func makeTrade(
        netProfit: Decimal = 50,
        direction: TradeDirection = .buy,
        symbol: String = "GBPUSD",
        rMultiple: Double = 1.5,
        tags: String = "",
        notes: String = ""
    ) -> Trade {
        Trade(
            id: 1, ticket: 100001, symbol: symbol, direction: direction,
            lots: 0.10, openTime: Date(), closeTime: Date(), durationMin: 60,
            openPrice: 1.25, closePrice: 1.26, sl: 1.24, tp: 1.27,
            netProfit: netProfit, maePips: 5.0, mfePips: 10.0,
            rMultiple: rMultiple, session: .london, dayOfWeek: "Mon", hour: 10,
            rangeSize: 40, sweepDepth: 10, usedFVG: false, volRegime: .med,
            hitBreakeven: false, scaledIn: false, magic: 12345, comment: "test",
            timeToMFEMin: 30, slDistPips: 20, slippagePips: 0.5,
            postClose15m: 5, postClose30m: 10, biasAtEntry: .with,
            notes: notes, tags: tags, importedAt: Date()
        )
    }

    // MARK: - Computed Properties

    func testIsWin() {
        XCTAssertTrue(makeTrade(netProfit: 50).isWin)
        XCTAssertFalse(makeTrade(netProfit: -50).isWin)
        XCTAssertFalse(makeTrade(netProfit: 0).isWin)
    }

    func testIsLoss() {
        XCTAssertTrue(makeTrade(netProfit: -50).isLoss)
        XCTAssertFalse(makeTrade(netProfit: 50).isLoss)
        XCTAssertFalse(makeTrade(netProfit: 0).isLoss)
    }

    func testProfitDouble() {
        let trade = makeTrade(netProfit: Decimal(string: "123.45")!)
        XCTAssertEqual(trade.profitDouble, 123.45, accuracy: 0.01)
    }

    func testProfitDoubleNegative() {
        let trade = makeTrade(netProfit: Decimal(string: "-67.89")!)
        XCTAssertEqual(trade.profitDouble, -67.89, accuracy: 0.01)
    }

    func testDirectionSymbol() {
        XCTAssertEqual(makeTrade(direction: .buy).directionSymbol, "↑")
        XCTAssertEqual(makeTrade(direction: .sell).directionSymbol, "↓")
    }

    func testPairDisplay() {
        XCTAssertEqual(makeTrade(symbol: "GBPUSD").pairDisplay, "GBP/USD")
        XCTAssertEqual(makeTrade(symbol: "EURUSD").pairDisplay, "EUR/USD")
        XCTAssertEqual(makeTrade(symbol: "USDJPY").pairDisplay, "USD/JPY")
    }

    // MARK: - Tags

    func testTagListEmpty() {
        let trade = makeTrade(tags: "")
        XCTAssertTrue(trade.tagList.isEmpty)
    }

    func testTagListSingle() {
        let trade = makeTrade(tags: "sniper")
        XCTAssertEqual(trade.tagList, ["sniper"])
    }

    func testTagListMultiple() {
        let trade = makeTrade(tags: "setup-A,sniper,FOMO")
        XCTAssertEqual(trade.tagList, ["setup-A", "sniper", "FOMO"])
    }

    func testTagListWithSpaces() {
        let trade = makeTrade(tags: "setup-A , sniper , FOMO")
        XCTAssertEqual(trade.tagList, ["setup-A", "sniper", "FOMO"])
    }

    func testTagListFiltersEmpty() {
        let trade = makeTrade(tags: "a,,b, ,c")
        XCTAssertEqual(trade.tagList, ["a", "b", "c"])
    }

    func testWithTag() {
        let trade = makeTrade(tags: "setup-A")
        let updated = trade.withTag("sniper")
        XCTAssertEqual(updated.tagList, ["setup-A", "sniper"])
    }

    func testWithTagNoDuplicate() {
        let trade = makeTrade(tags: "setup-A,sniper")
        let updated = trade.withTag("sniper")
        XCTAssertEqual(updated.tagList, ["setup-A", "sniper"])
    }

    func testWithoutTag() {
        let trade = makeTrade(tags: "setup-A,sniper,FOMO")
        let updated = trade.withoutTag("sniper")
        XCTAssertEqual(updated.tagList, ["setup-A", "FOMO"])
    }

    func testWithoutTagNotPresent() {
        let trade = makeTrade(tags: "setup-A")
        let updated = trade.withoutTag("nonexistent")
        XCTAssertEqual(updated.tagList, ["setup-A"])
    }

    // MARK: - Enums

    func testTradeDirectionRawValues() {
        XCTAssertEqual(TradeDirection.buy.rawValue, "BUY")
        XCTAssertEqual(TradeDirection.sell.rawValue, "SELL")
    }

    func testTradingSessionDisplayNames() {
        XCTAssertEqual(TradingSession.asian.displayName, "Asian")
        XCTAssertEqual(TradingSession.london.displayName, "London")
        XCTAssertEqual(TradingSession.nyOverlap.displayName, "NY Overlap")
        XCTAssertEqual(TradingSession.ny.displayName, "New York")
        XCTAssertEqual(TradingSession.late.displayName, "Late")
    }

    func testVolatilityRegimeRawValues() {
        XCTAssertEqual(VolatilityRegime.low.rawValue, "LOW")
        XCTAssertEqual(VolatilityRegime.med.rawValue, "MED")
        XCTAssertEqual(VolatilityRegime.high.rawValue, "HIGH")
    }

    func testBiasAlignmentRawValues() {
        XCTAssertEqual(BiasAlignment.with.rawValue, "WITH")
        XCTAssertEqual(BiasAlignment.against.rawValue, "AGAINST")
        XCTAssertEqual(BiasAlignment.neutral.rawValue, "NEUTRAL")
    }
}
