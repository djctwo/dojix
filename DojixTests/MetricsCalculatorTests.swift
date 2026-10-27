import XCTest
@testable import Dojix

final class MetricsCalculatorTests: XCTestCase {

    // MARK: - Test Helpers

    private func makeTrade(
        ticket: Int64 = 1,
        symbol: String = "GBPUSD",
        direction: TradeDirection = .buy,
        netProfit: Decimal,
        rMultiple: Double = 1.0,
        maePips: Double = 5.0,
        mfePips: Double = 10.0,
        session: TradingSession = .london,
        dayOfWeek: String = "Mon",
        hour: Int = 10,
        durationMin: Int = 60,
        closeTime: Date = Date(),
        biasAtEntry: BiasAlignment = .with,
        volRegime: VolatilityRegime = .med
    ) -> Trade {
        Trade(
            id: nil, ticket: ticket, symbol: symbol, direction: direction,
            lots: 0.10, openTime: closeTime.addingTimeInterval(-Double(durationMin * 60)),
            closeTime: closeTime, durationMin: durationMin,
            openPrice: 1.25, closePrice: 1.26, sl: 1.24, tp: 1.27,
            netProfit: netProfit, maePips: maePips, mfePips: mfePips,
            rMultiple: rMultiple, session: session, dayOfWeek: dayOfWeek, hour: hour,
            rangeSize: 40, sweepDepth: 10, usedFVG: false, volRegime: volRegime,
            hitBreakeven: false, scaledIn: false, magic: 0, comment: "",
            timeToMFEMin: 30, slDistPips: 20, slippagePips: 0.5,
            postClose15m: 5, postClose30m: 10, biasAtEntry: biasAtEntry,
            importedAt: Date()
        )
    }

    // MARK: - Portfolio Metrics

    func testEmptyTrades() {
        let metrics = MetricsCalculator.calculate(from: [])
        XCTAssertEqual(metrics.totalTrades, 0)
        XCTAssertEqual(metrics.wins, 0)
        XCTAssertEqual(metrics.losses, 0)
        XCTAssertEqual(metrics.winRate, 0)
        XCTAssertEqual(metrics.totalProfit, 0)
    }

    func testSingleWinningTrade() {
        let trades = [makeTrade(netProfit: 50)]
        let metrics = MetricsCalculator.calculate(from: trades)

        XCTAssertEqual(metrics.totalTrades, 1)
        XCTAssertEqual(metrics.wins, 1)
        XCTAssertEqual(metrics.losses, 0)
        XCTAssertEqual(metrics.winRate, 100.0)
        XCTAssertEqual(metrics.totalProfit, 50.0, accuracy: 0.01)
        XCTAssertEqual(metrics.grossProfit, 50.0, accuracy: 0.01)
        XCTAssertEqual(metrics.grossLoss, 0)
        XCTAssertEqual(metrics.averageWin, 50.0, accuracy: 0.01)
        XCTAssertEqual(metrics.averageLoss, 0)
        XCTAssertEqual(metrics.bestTrade, 50.0, accuracy: 0.01)
    }

    func testSingleLosingTrade() {
        let trades = [makeTrade(netProfit: -30)]
        let metrics = MetricsCalculator.calculate(from: trades)

        XCTAssertEqual(metrics.totalTrades, 1)
        XCTAssertEqual(metrics.wins, 0)
        XCTAssertEqual(metrics.losses, 1)
        XCTAssertEqual(metrics.winRate, 0)
        XCTAssertEqual(metrics.totalProfit, -30.0, accuracy: 0.01)
        XCTAssertEqual(metrics.worstTrade, -30.0, accuracy: 0.01)
    }

    func testMixedTrades() {
        let baseDate = Date()
        let trades = [
            makeTrade(ticket: 1, netProfit: 100, closeTime: baseDate.addingTimeInterval(0)),
            makeTrade(ticket: 2, netProfit: 50, closeTime: baseDate.addingTimeInterval(100)),
            makeTrade(ticket: 3, netProfit: -30, closeTime: baseDate.addingTimeInterval(200)),
            makeTrade(ticket: 4, netProfit: -20, closeTime: baseDate.addingTimeInterval(300)),
            makeTrade(ticket: 5, netProfit: 80, closeTime: baseDate.addingTimeInterval(400)),
        ]
        let metrics = MetricsCalculator.calculate(from: trades)

        XCTAssertEqual(metrics.totalTrades, 5)
        XCTAssertEqual(metrics.wins, 3)
        XCTAssertEqual(metrics.losses, 2)
        XCTAssertEqual(metrics.winRate, 60.0, accuracy: 0.01)
        XCTAssertEqual(metrics.totalProfit, 180.0, accuracy: 0.01)
        XCTAssertEqual(metrics.grossProfit, 230.0, accuracy: 0.01)
        XCTAssertEqual(metrics.grossLoss, 50.0, accuracy: 0.01)
        XCTAssertEqual(metrics.profitFactor, 230.0 / 50.0, accuracy: 0.01)
        XCTAssertEqual(metrics.averageWin, 230.0 / 3.0, accuracy: 0.01)
        XCTAssertEqual(metrics.averageLoss, 50.0 / 2.0, accuracy: 0.01)
        XCTAssertEqual(metrics.bestTrade, 100.0, accuracy: 0.01)
        XCTAssertEqual(metrics.worstTrade, -30.0, accuracy: 0.01)
    }

    func testProfitFactorAllWins() {
        let trades = [
            makeTrade(ticket: 1, netProfit: 50),
            makeTrade(ticket: 2, netProfit: 100),
        ]
        let metrics = MetricsCalculator.calculate(from: trades)
        XCTAssertEqual(metrics.profitFactor, .infinity)
    }

    func testMaxDrawdown() {
        let baseDate = Date()
        // Equity curve: 100, 150, 50, 30, 130 → peak 150, worst 30 → DD = 120
        let trades = [
            makeTrade(ticket: 1, netProfit: 100, closeTime: baseDate.addingTimeInterval(0)),
            makeTrade(ticket: 2, netProfit: 50, closeTime: baseDate.addingTimeInterval(100)),
            makeTrade(ticket: 3, netProfit: -100, closeTime: baseDate.addingTimeInterval(200)),
            makeTrade(ticket: 4, netProfit: -20, closeTime: baseDate.addingTimeInterval(300)),
            makeTrade(ticket: 5, netProfit: 100, closeTime: baseDate.addingTimeInterval(400)),
        ]
        let metrics = MetricsCalculator.calculate(from: trades)
        XCTAssertEqual(metrics.maxDrawdown, 120.0, accuracy: 0.01)
    }

    func testStreaks() {
        let baseDate = Date()
        let trades = [
            makeTrade(ticket: 1, netProfit: 10, closeTime: baseDate.addingTimeInterval(0)),
            makeTrade(ticket: 2, netProfit: 20, closeTime: baseDate.addingTimeInterval(100)),
            makeTrade(ticket: 3, netProfit: 30, closeTime: baseDate.addingTimeInterval(200)),
            makeTrade(ticket: 4, netProfit: -10, closeTime: baseDate.addingTimeInterval(300)),
            makeTrade(ticket: 5, netProfit: -20, closeTime: baseDate.addingTimeInterval(400)),
            makeTrade(ticket: 6, netProfit: 15, closeTime: baseDate.addingTimeInterval(500)),
        ]
        let metrics = MetricsCalculator.calculate(from: trades)

        XCTAssertEqual(metrics.maxWinStreak, 3)
        XCTAssertEqual(metrics.maxLossStreak, 2)
        XCTAssertEqual(metrics.currentStreak, 1) // last trade is a win
    }

    func testCurrentStreakNegative() {
        let baseDate = Date()
        let trades = [
            makeTrade(ticket: 1, netProfit: 50, closeTime: baseDate.addingTimeInterval(0)),
            makeTrade(ticket: 2, netProfit: -10, closeTime: baseDate.addingTimeInterval(100)),
            makeTrade(ticket: 3, netProfit: -20, closeTime: baseDate.addingTimeInterval(200)),
        ]
        let metrics = MetricsCalculator.calculate(from: trades)
        XCTAssertEqual(metrics.currentStreak, -2) // last 2 trades are losses
    }

    func testAverageDuration() {
        let trades = [
            makeTrade(ticket: 1, netProfit: 10, durationMin: 30),
            makeTrade(ticket: 2, netProfit: 20, durationMin: 60),
            makeTrade(ticket: 3, netProfit: -5, durationMin: 90),
        ]
        let metrics = MetricsCalculator.calculate(from: trades)
        XCTAssertEqual(metrics.averageDuration, 60) // (30+60+90)/3
    }

    // MARK: - Edge Breakdowns

    func testEdgeBySession() {
        let trades = [
            makeTrade(ticket: 1, netProfit: 100, session: .london),
            makeTrade(ticket: 2, netProfit: 50, session: .london),
            makeTrade(ticket: 3, netProfit: -30, session: .asian),
            makeTrade(ticket: 4, netProfit: 80, session: .ny),
        ]
        let edges = MetricsCalculator.edgeBySession(from: trades)

        XCTAssertEqual(edges.count, 3)
        // Should be sorted by profit descending
        XCTAssertEqual(edges[0].label, "London")
        XCTAssertEqual(edges[0].profit, 150.0, accuracy: 0.01)
        XCTAssertEqual(edges[0].tradeCount, 2)
    }

    func testEdgeByPair() {
        let trades = [
            makeTrade(ticket: 1, symbol: "GBPUSD", netProfit: 100),
            makeTrade(ticket: 2, symbol: "GBPUSD", netProfit: -20),
            makeTrade(ticket: 3, symbol: "EURUSD", netProfit: 50),
        ]
        let edges = MetricsCalculator.edgeByPair(from: trades)

        XCTAssertEqual(edges.count, 2)
        XCTAssertEqual(edges[0].label, "GBPUSD")
        XCTAssertEqual(edges[0].profit, 80.0, accuracy: 0.01)
    }

    func testEdgeByHour() {
        let trades = [
            makeTrade(ticket: 1, netProfit: 100, hour: 10),
            makeTrade(ticket: 2, netProfit: -30, hour: 10),
            makeTrade(ticket: 3, netProfit: 50, hour: 14),
        ]
        let edges = MetricsCalculator.edgeByHour(from: trades)

        XCTAssertEqual(edges.count, 2)
        // 10:00 = 70, 14:00 = 50
        XCTAssertEqual(edges[0].profit, 70.0, accuracy: 0.01)
        XCTAssertEqual(edges[0].label, "10:00")
    }

    func testEdgeByDay() {
        let trades = [
            makeTrade(ticket: 1, netProfit: 100, dayOfWeek: "Mon"),
            makeTrade(ticket: 2, netProfit: 50, dayOfWeek: "Tue"),
            makeTrade(ticket: 3, netProfit: -80, dayOfWeek: "Mon"),
        ]
        let edges = MetricsCalculator.edgeByDay(from: trades)

        XCTAssertEqual(edges.count, 2)
        XCTAssertEqual(edges[0].label, "Tue") // 50 > 20
    }

    func testEdgeByBias() {
        let trades = [
            makeTrade(ticket: 1, netProfit: 100, biasAtEntry: .with),
            makeTrade(ticket: 2, netProfit: -50, biasAtEntry: .against),
            makeTrade(ticket: 3, netProfit: 30, biasAtEntry: .with),
        ]
        let edges = MetricsCalculator.edgeByBias(from: trades)

        XCTAssertEqual(edges.count, 2)
        XCTAssertEqual(edges[0].label, "WITH")
        XCTAssertEqual(edges[0].profit, 130.0, accuracy: 0.01)
    }

    func testEdgeByVolRegime() {
        let trades = [
            makeTrade(ticket: 1, netProfit: 80, volRegime: .med),
            makeTrade(ticket: 2, netProfit: -30, volRegime: .high),
            makeTrade(ticket: 3, netProfit: 40, volRegime: .low),
        ]
        let edges = MetricsCalculator.edgeByVolRegime(from: trades)

        XCTAssertEqual(edges.count, 3)
        XCTAssertEqual(edges[0].label, "MED")
        XCTAssertEqual(edges[0].profit, 80.0, accuracy: 0.01)
    }

    func testWinRateInEdgeBreakdown() {
        let trades = [
            makeTrade(ticket: 1, netProfit: 100, session: .london),
            makeTrade(ticket: 2, netProfit: -20, session: .london),
            makeTrade(ticket: 3, netProfit: 30, session: .london),
        ]
        let edges = MetricsCalculator.edgeBySession(from: trades)

        XCTAssertEqual(edges[0].winRate, 200.0 / 3.0, accuracy: 0.1) // 2/3 * 100
    }
}
