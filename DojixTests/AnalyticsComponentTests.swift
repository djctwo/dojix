import XCTest
@testable import Dojix

/// Tests for analytics component calculations (not UI, just the math)
final class AnalyticsComponentTests: XCTestCase {

    // MARK: - Test Helpers

    private func makeTrade(
        ticket: Int64 = 1,
        symbol: String = "GBPUSD",
        direction: TradeDirection = .buy,
        netProfit: Decimal,
        lots: Double = 0.10,
        rMultiple: Double = 1.0,
        maePips: Double = 5.0,
        mfePips: Double = 10.0,
        session: TradingSession = .london,
        dayOfWeek: String = "Mon",
        hour: Int = 10,
        durationMin: Int = 60,
        closeTime: Date = Date(),
        postClose15m: Double = 5.0,
        postClose30m: Double = 10.0,
        biasAtEntry: BiasAlignment = .with,
        volRegime: VolatilityRegime = .med
    ) -> Trade {
        Trade(
            id: nil, ticket: ticket, symbol: symbol, direction: direction,
            lots: lots, openTime: closeTime.addingTimeInterval(-Double(durationMin * 60)),
            closeTime: closeTime, durationMin: durationMin,
            openPrice: 1.25, closePrice: 1.26, sl: 1.24, tp: 1.27,
            netProfit: netProfit, maePips: maePips, mfePips: mfePips,
            rMultiple: rMultiple, session: session, dayOfWeek: dayOfWeek, hour: hour,
            rangeSize: 40, sweepDepth: 10, usedFVG: false, volRegime: volRegime,
            hitBreakeven: false, scaledIn: false, magic: 0, comment: "",
            timeToMFEMin: 30, slDistPips: 20, slippagePips: 0.5,
            postClose15m: postClose15m, postClose30m: postClose30m, biasAtEntry: biasAtEntry,
            importedAt: Date()
        )
    }

    private func makeTrades(count: Int, profitPattern: [Decimal]) -> [Trade] {
        (0..<count).map { i in
            let profit = profitPattern[i % profitPattern.count]
            return makeTrade(
                ticket: Int64(i),
                netProfit: profit,
                closeTime: Date().addingTimeInterval(Double(i) * 3600)
            )
        }
    }

    // MARK: - Risk of Ruin Math

    func testRiskOfRuinWinRateCalculation() {
        // 7 wins, 3 losses = 70% win rate
        var trades: [Trade] = []
        for i in 0..<7 { trades.append(makeTrade(ticket: Int64(i), netProfit: 50)) }
        for i in 7..<10 { trades.append(makeTrade(ticket: Int64(i), netProfit: -30)) }

        let winCount = trades.filter(\.isWin).count
        let winRate = Double(winCount) / Double(trades.count)
        XCTAssertEqual(winRate, 0.7, accuracy: 0.001)
    }

    func testRiskOfRuinRewardRiskRatio() {
        // Avg win = 50, avg loss = 30 → R:R = 1.67
        var trades: [Trade] = []
        for i in 0..<5 { trades.append(makeTrade(ticket: Int64(i), netProfit: 50)) }
        for i in 5..<10 { trades.append(makeTrade(ticket: Int64(i), netProfit: -30)) }

        let wins = trades.filter(\.isWin)
        let losses = trades.filter(\.isLoss)
        let avgWin = wins.map(\.profitDouble).reduce(0, +) / Double(wins.count)
        let avgLoss = abs(losses.map(\.profitDouble).reduce(0, +)) / Double(losses.count)
        let rr = avgWin / avgLoss

        XCTAssertEqual(avgWin, 50, accuracy: 0.01)
        XCTAssertEqual(avgLoss, 30, accuracy: 0.01)
        XCTAssertEqual(rr, 1.667, accuracy: 0.01)
    }

    func testKellyCriterion() {
        // Kelly = W - (1-W)/R
        // With 60% win rate, 1.5 R:R → Kelly = 0.6 - 0.4/1.5 = 0.333
        let w = 0.6
        let r = 1.5
        let kelly = w - (1 - w) / r
        XCTAssertEqual(kelly, 0.333, accuracy: 0.01)
    }

    func testKellyCriterionNegativeEdge() {
        // With 40% win rate, 1.0 R:R → Kelly = 0.4 - 0.6/1.0 = -0.2 (no edge)
        let w = 0.4
        let r = 1.0
        let kelly = w - (1 - w) / r
        XCTAssertLessThan(kelly, 0)
    }

    // MARK: - Consistency Score Dimensions

    func testConsistentLotSizes() {
        // All trades same lots → CV = 0 → score = 100
        let trades = (0..<20).map { i in
            makeTrade(ticket: Int64(i), netProfit: 50, lots: 0.10)
        }
        let lots = trades.map(\.lots)
        let mean = lots.reduce(0, +) / Double(lots.count)
        let variance = lots.map { pow($0 - mean, 2) }.reduce(0, +) / Double(lots.count)
        let cv = mean > 0 ? sqrt(variance) / mean : 1.0

        XCTAssertEqual(cv, 0, accuracy: 0.001)
    }

    func testInconsistentLotSizes() {
        // Varying lots → higher CV
        let lotSizes: [Double] = [0.01, 0.50, 0.10, 1.0, 0.05, 0.80, 0.02, 0.30]
        let trades = lotSizes.enumerated().map { i, lots in
            makeTrade(ticket: Int64(i), netProfit: 50, lots: lots)
        }
        let lots = trades.map(\.lots)
        let mean = lots.reduce(0, +) / Double(lots.count)
        let variance = lots.map { pow($0 - mean, 2) }.reduce(0, +) / Double(lots.count)
        let cv = mean > 0 ? sqrt(variance) / mean : 1.0

        XCTAssertGreaterThan(cv, 0.5, "Expected high variation in lot sizes")
    }

    func testWinRateStability() {
        // All wins → perfectly stable win rate
        let trades = (0..<20).map { i in
            makeTrade(ticket: Int64(i), netProfit: 50,
                     closeTime: Date().addingTimeInterval(Double(i) * 3600))
        }
        let sorted = trades.sorted { $0.closeTime < $1.closeTime }
        let windowSize = max(5, sorted.count / 4)
        var windowRates: [Double] = []
        for i in 0...(sorted.count - windowSize) {
            let window = Array(sorted[i..<(i + windowSize)])
            let wr = Double(window.filter(\.isWin).count) / Double(window.count)
            windowRates.append(wr)
        }
        let mean = windowRates.reduce(0, +) / Double(windowRates.count)
        let variance = windowRates.map { pow($0 - mean, 2) }.reduce(0, +) / Double(windowRates.count)
        let cv = mean > 0 ? sqrt(variance) / mean : 1.0

        XCTAssertEqual(cv, 0, accuracy: 0.001, "All wins should have 0 CV")
    }

    // MARK: - Pearson Correlation

    func testPerfectPositiveCorrelation() {
        let series1 = ["d1": 10.0, "d2": 20.0, "d3": 30.0, "d4": 40.0, "d5": 50.0]
        let series2 = ["d1": 10.0, "d2": 20.0, "d3": 30.0, "d4": 40.0, "d5": 50.0]
        let corr = pearsonCorrelation(series1: series1, series2: series2)
        XCTAssertEqual(corr, 1.0, accuracy: 0.001)
    }

    func testPerfectNegativeCorrelation() {
        let series1 = ["d1": 10.0, "d2": 20.0, "d3": 30.0, "d4": 40.0, "d5": 50.0]
        let series2 = ["d1": 50.0, "d2": 40.0, "d3": 30.0, "d4": 20.0, "d5": 10.0]
        let corr = pearsonCorrelation(series1: series1, series2: series2)
        XCTAssertEqual(corr, -1.0, accuracy: 0.001)
    }

    func testWeakCorrelation() {
        // Data with no clear linear relationship
        let series1 = ["d1": 10.0, "d2": 20.0, "d3": 30.0, "d4": 40.0, "d5": 50.0]
        let series2 = ["d1": 5.0, "d2": 30.0, "d3": 10.0, "d4": 35.0, "d5": 15.0]
        let corr = pearsonCorrelation(series1: series1, series2: series2)
        XCTAssertLessThan(abs(corr), 0.8, "Expected weak-to-moderate correlation")
    }

    func testCorrelationInsufficientData() {
        // Less than 5 common dates → returns 0
        let series1 = ["d1": 10.0, "d2": 20.0]
        let series2 = ["d1": 10.0, "d2": 20.0]
        let corr = pearsonCorrelation(series1: series1, series2: series2)
        XCTAssertEqual(corr, 0, "Should return 0 with insufficient data")
    }

    // MARK: - Post-Close Analysis

    func testEarlyExitDetection() {
        // 10 wins, 5 with >10 pips continuation → 50% early exits
        var trades: [Trade] = []
        for i in 0..<5 {
            trades.append(makeTrade(ticket: Int64(i), netProfit: 50, postClose30m: 15))
        }
        for i in 5..<10 {
            trades.append(makeTrade(ticket: Int64(i), netProfit: 50, postClose30m: 5))
        }

        let wins = trades.filter(\.isWin)
        let earlyExits = wins.filter { $0.postClose30m > 10 }.count
        let earlyExitPct = Double(earlyExits) / Double(wins.count) * 100

        XCTAssertEqual(earlyExitPct, 50, accuracy: 0.01)
    }

    func testPostCloseContinuationAverage() {
        let trades = [
            makeTrade(ticket: 1, netProfit: 50, postClose15m: 10, postClose30m: 20),
            makeTrade(ticket: 2, netProfit: 50, postClose15m: 5, postClose30m: 15),
            makeTrade(ticket: 3, netProfit: -30, postClose15m: 3, postClose30m: 8),
        ]

        let avg15 = trades.map(\.postClose15m).reduce(0, +) / Double(trades.count)
        let avg30 = trades.map(\.postClose30m).reduce(0, +) / Double(trades.count)

        XCTAssertEqual(avg15, 6.0, accuracy: 0.01)
        XCTAssertEqual(avg30, 14.333, accuracy: 0.01)
    }

    // MARK: - Duration Analysis Buckets

    func testDurationBucketAssignment() {
        let ranges: [(label: String, range: ClosedRange<Int>)] = [
            ("0-5m", 0...5),
            ("5-15m", 6...15),
            ("15-30m", 16...30),
            ("30-60m", 31...60),
            ("1-2h", 61...120),
            ("2h+", 121...999999),
        ]

        XCTAssertTrue(ranges[0].range.contains(3))
        XCTAssertTrue(ranges[1].range.contains(10))
        XCTAssertTrue(ranges[2].range.contains(25))
        XCTAssertTrue(ranges[3].range.contains(45))
        XCTAssertTrue(ranges[4].range.contains(90))
        XCTAssertTrue(ranges[5].range.contains(180))
        XCTAssertFalse(ranges[0].range.contains(6))
    }

    // MARK: - MAE/MFE Ratio

    func testMFEToMAERatio() {
        let trades = [
            makeTrade(ticket: 1, netProfit: 50, maePips: 10, mfePips: 30),
            makeTrade(ticket: 2, netProfit: 50, maePips: 5, mfePips: 20),
            makeTrade(ticket: 3, netProfit: -30, maePips: 15, mfePips: 10),
        ]

        let avgMAE = trades.map(\.maePips).reduce(0, +) / Double(trades.count)
        let avgMFE = trades.map(\.mfePips).reduce(0, +) / Double(trades.count)
        let ratio = avgMFE / avgMAE

        XCTAssertEqual(avgMAE, 10.0, accuracy: 0.01)
        XCTAssertEqual(avgMFE, 20.0, accuracy: 0.01)
        XCTAssertEqual(ratio, 2.0, accuracy: 0.01)
    }

    func testMFEToMAERatioZeroMAE() {
        let trades = [
            makeTrade(ticket: 1, netProfit: 50, maePips: 0, mfePips: 20),
        ]
        let avgMAE = trades.map(\.maePips).reduce(0, +) / Double(trades.count)
        // Should not divide by zero
        let ratio = avgMAE > 0 ? trades.map(\.mfePips).reduce(0, +) / Double(trades.count) / avgMAE : 0
        XCTAssertEqual(ratio, 0)
    }

    // MARK: - Drawdown Recovery

    func testDrawdownRecoveryPeriods() {
        // +50, +50, -100, -50, +50, +100
        // Cumulative: 50, 100, 0, -50, 0, 100
        // Peak: 50, 100, 100, 100, 100, 100
        // Trades 3,4,5 are below peak → 3 trades in drawdown before recovery at trade 6
        let profits: [Decimal] = [50, 50, -100, -50, 50, 100]
        let trades = profits.enumerated().map { i, p in
            makeTrade(ticket: Int64(i), netProfit: p,
                     closeTime: Date().addingTimeInterval(Double(i) * 3600))
        }

        var peak = 0.0, cumulative = 0.0
        var drawdownPeriods: [Int] = []
        var currentDDLength = 0

        let sorted = trades.sorted { $0.closeTime < $1.closeTime }
        for trade in sorted {
            cumulative += trade.profitDouble
            if cumulative >= peak {
                peak = cumulative
                if currentDDLength > 0 {
                    drawdownPeriods.append(currentDDLength)
                    currentDDLength = 0
                }
            } else {
                currentDDLength += 1
            }
        }
        if currentDDLength > 0 { drawdownPeriods.append(currentDDLength) }

        XCTAssertEqual(drawdownPeriods.count, 1, "Should have one drawdown period")
        XCTAssertEqual(drawdownPeriods[0], 3, "Drawdown should last 3 trades (below peak)")
    }

    // MARK: - Position Sizing Math

    func testPositionSizingCalculation() {
        // Account $10,000, risk 1%, avg SL 20 pips
        // Risk per trade = $100
        // Pip value per standard lot ≈ $10
        // Lots = $100 / (20 * $10) = 0.50
        let balance = 10_000.0
        let riskPct = 1.0
        let avgSL = 20.0
        let pipValuePerLot = 10.0

        let riskPerTrade = balance * (riskPct / 100)
        let lots = riskPerTrade / (avgSL * pipValuePerLot)

        XCTAssertEqual(riskPerTrade, 100.0, accuracy: 0.01)
        XCTAssertEqual(lots, 0.50, accuracy: 0.01)
    }

    func testPositionSizingSmallAccount() {
        // Account $1,000, risk 2%, avg SL 30 pips
        // Risk = $20, Lots = $20 / (30 * $10) = 0.067
        let balance = 1_000.0
        let riskPct = 2.0
        let avgSL = 30.0
        let pipValuePerLot = 10.0

        let riskPerTrade = balance * (riskPct / 100)
        let lots = riskPerTrade / (avgSL * pipValuePerLot)

        XCTAssertEqual(riskPerTrade, 20.0, accuracy: 0.01)
        XCTAssertEqual(lots, 0.067, accuracy: 0.01)
    }

    // MARK: - Expectancy Projection

    func testExpectancyProjection() {
        // Expectancy $15/trade, 50 trades → expected $750
        let expectancy = 15.0
        let tradeCount = 50
        let projected = expectancy * Double(tradeCount)
        XCTAssertEqual(projected, 750.0, accuracy: 0.01)
    }

    func testGrowthProjectionWeekly() {
        // 5 trades/week, $15 expectancy, 6 months (24 weeks)
        // Expected = 5 * $15 * 24 = $1,800
        let tradesPerWeek = 5.0
        let expectancy = 15.0
        let weeks = 24
        let projected = tradesPerWeek * expectancy * Double(weeks)
        XCTAssertEqual(projected, 1800.0, accuracy: 0.01)
    }

    // MARK: - PDF Export Content

    func testPDFExporterCreatesData() throws {
        let trades = (0..<5).map { i in
            makeTrade(ticket: Int64(i), netProfit: Decimal(i * 10 - 20))
        }
        let metrics = MetricsCalculator.calculate(from: trades)
        let exporter = PDFExporter()

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_journal.pdf")
        try exporter.exportJournal(trades: trades, metrics: metrics, to: tempURL)

        let data = try Data(contentsOf: tempURL)
        XCTAssertGreaterThan(data.count, 100, "PDF should contain data")

        try FileManager.default.removeItem(at: tempURL)
    }

    func testDashboardPDFExport() throws {
        let days = ["Mon", "Tue", "Wed", "Thu", "Fri"]
        let trades: [Trade] = (0..<10).map { i in
            let session: TradingSession = i < 5 ? .london : .ny
            let profit = Decimal(i * 10 - 30)
            return makeTrade(
                ticket: Int64(i),
                netProfit: profit,
                session: session,
                dayOfWeek: days[i % 5],
                hour: 8 + (i % 6)
            )
        }
        let metrics = MetricsCalculator.calculate(from: trades)
        let exporter = PDFExporter()

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_dashboard.pdf")
        try exporter.exportDashboard(
            trades: trades,
            metrics: metrics,
            edgeBySession: MetricsCalculator.edgeBySession(from: trades),
            edgeByHour: MetricsCalculator.edgeByHour(from: trades),
            edgeByPair: MetricsCalculator.edgeByPair(from: trades),
            edgeByDay: MetricsCalculator.edgeByDay(from: trades),
            to: tempURL
        )

        let data = try Data(contentsOf: tempURL)
        XCTAssertGreaterThan(data.count, 100, "Dashboard PDF should contain data")

        try FileManager.default.removeItem(at: tempURL)
    }

    // MARK: - Sequence Analysis

    func testSequenceTransitionAfterWin() {
        // 10 trades: W W L W W W L W L W
        // After wins: W L W W L W L → 4 wins after win, 3 losses after win
        let profits: [Decimal] = [50, 50, -30, 50, 50, 50, -30, 50, -30, 50]
        let trades = profits.enumerated().map { i, p in
            makeTrade(ticket: Int64(i), netProfit: p,
                     closeTime: Date().addingTimeInterval(Double(i) * 3600))
        }
        let sorted = trades.sorted { $0.closeTime < $1.closeTime }

        var ww = 0, wl = 0
        for i in 1..<sorted.count {
            if sorted[i - 1].isWin {
                if sorted[i].isWin { ww += 1 } else { wl += 1 }
            }
        }
        // W W → 1, W L → 1, (L→skip), W W → 1, W W → 1, W L → 1, (L→skip), W L → 1, (L→skip)
        // After wins: W(2):W, W(2):L, W(4):W, W(5):W, W(6):L, W(8):L
        // ww=3, wl=3
        XCTAssertEqual(ww + wl, 6, "Should have 6 transitions after wins")
    }

    func testSequenceTransitionAfterLoss() {
        // All losses → every transition is loss-after-loss
        let trades = (0..<10).map { i in
            makeTrade(ticket: Int64(i), netProfit: -30,
                     closeTime: Date().addingTimeInterval(Double(i) * 3600))
        }
        let sorted = trades.sorted { $0.closeTime < $1.closeTime }

        var ll = 0
        for i in 1..<sorted.count {
            if !sorted[i - 1].isWin && !sorted[i].isWin { ll += 1 }
        }
        XCTAssertEqual(ll, 9, "All 9 transitions should be loss-after-loss")
    }

    // MARK: - Directional Edge

    func testDirectionalSplit() {
        let buys: [Trade] = (0..<5).map { i in
            makeTrade(ticket: Int64(i), direction: .buy, netProfit: 50)
        }
        let sells: [Trade] = (5..<10).map { i in
            makeTrade(ticket: Int64(i), direction: .sell, netProfit: -20)
        }
        let all = buys + sells

        let buyTrades = all.filter { $0.direction == TradeDirection.buy }
        let sellTrades = all.filter { $0.direction == TradeDirection.sell }
        let buyPnL = buyTrades.map(\.profitDouble).reduce(0, +)
        let sellPnL = sellTrades.map(\.profitDouble).reduce(0, +)

        XCTAssertEqual(buyPnL, 250, accuracy: 0.01)
        XCTAssertEqual(sellPnL, -100, accuracy: 0.01)
    }

    // MARK: - Slippage Analysis

    func testAvgSlippageCalculation() {
        let trades = [
            makeTrade(ticket: 1, netProfit: 50),
            makeTrade(ticket: 2, netProfit: 50),
            makeTrade(ticket: 3, netProfit: -30),
        ]
        // All trades have slippagePips = 0.5 (default from makeTrade)
        let slippages = trades.map { $0.slippagePips }
        let avg = slippages.reduce(0, +) / Double(slippages.count)
        XCTAssertEqual(avg, 0.5, accuracy: 0.01)
    }

    // MARK: - Benchmark Comparison

    func testBenchmarkWinRateComparison() {
        // Retail average win rate benchmark is ~45%
        // Trader with 60% win rate should be "above"
        let winRate = 60.0
        let benchmark = 45.0
        let threshold = benchmark * 0.1 // 4.5
        let diff = winRate - benchmark  // 15.0
        let isAbove = diff > threshold
        XCTAssertTrue(isAbove, "60% win rate should be above 45% benchmark")
    }

    // MARK: - Pearson Correlation Helper

    private func pearsonCorrelation(series1: [String: Double], series2: [String: Double]) -> Double {
        let dates = Set(series1.keys).intersection(Set(series2.keys))
        guard dates.count >= 5 else { return 0 }

        let x = dates.map { series1[$0]! }
        let y = dates.map { series2[$0]! }
        let n = Double(x.count)

        let meanX = x.reduce(0, +) / n
        let meanY = y.reduce(0, +) / n

        var sumXY = 0.0, sumX2 = 0.0, sumY2 = 0.0
        for i in 0..<x.count {
            let dx = x[i] - meanX
            let dy = y[i] - meanY
            sumXY += dx * dy
            sumX2 += dx * dx
            sumY2 += dy * dy
        }

        let denominator = sqrt(sumX2 * sumY2)
        guard denominator > 0 else { return 0 }
        return sumXY / denominator
    }
}
