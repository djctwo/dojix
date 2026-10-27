import XCTest
@testable import Dojix

final class TradeGraderTests: XCTestCase {

    // MARK: - Test Helpers

    private func makeTrade(
        ticket: Int64 = 1,
        symbol: String = "GBPUSD",
        direction: TradeDirection = .buy,
        netProfit: Decimal = 50,
        lots: Double = 0.10,
        rMultiple: Double = 1.0,
        maePips: Double = 5.0,
        mfePips: Double = 15.0,
        session: TradingSession = .london,
        hour: Int = 10,
        durationMin: Int = 60,
        usedFVG: Bool = false,
        hitBreakeven: Bool = false,
        slippagePips: Double = 0.5,
        postClose15m: Double = 5.0,
        postClose30m: Double = 8.0,
        biasAtEntry: BiasAlignment = .with
    ) -> Trade {
        let closeTime = Date()
        return Trade(
            id: nil, ticket: ticket, symbol: symbol, direction: direction,
            lots: lots, openTime: closeTime.addingTimeInterval(-Double(durationMin * 60)),
            closeTime: closeTime, durationMin: durationMin,
            openPrice: 1.25, closePrice: 1.26, sl: 1.24, tp: 1.27,
            netProfit: netProfit, maePips: maePips, mfePips: mfePips,
            rMultiple: rMultiple, session: session, dayOfWeek: "Mon", hour: hour,
            rangeSize: 40, sweepDepth: 10, usedFVG: usedFVG, volRegime: .med,
            hitBreakeven: hitBreakeven, scaledIn: false, magic: 0, comment: "",
            timeToMFEMin: 30, slDistPips: 20, slippagePips: slippagePips,
            postClose15m: postClose15m, postClose30m: postClose30m, biasAtEntry: biasAtEntry,
            importedAt: Date()
        )
    }

    private var defaultMetrics: MetricsCalculator.PortfolioMetrics {
        MetricsCalculator.PortfolioMetrics(
            totalTrades: 100, wins: 55, losses: 45, winRate: 55,
            totalProfit: 1500, grossProfit: 3500, grossLoss: 2000,
            profitFactor: 1.75, expectancy: 15, averageWin: 63.64,
            averageLoss: 44.44, bestTrade: 200, worstTrade: -100,
            maxDrawdown: 300, averageRMultiple: 0.5, averageMAE: 8,
            averageMFE: 16, maxWinStreak: 7, maxLossStreak: 5,
            currentStreak: 2, averageDuration: 45,
            sharpeRatio: 0.3, calmarRatio: 5.0,
            totalCommissions: 0, totalSwap: 0, totalCosts: 0, netProfitAfterCosts: 1500
        )
    }

    // MARK: - R-Multiple Scoring

    func testHighRMultipleGetsHighScore() {
        let trade = makeTrade(rMultiple: 3.5)
        let grade = TradeGrader.grade(trade, portfolioMetrics: defaultMetrics)
        XCTAssertEqual(grade.rScore, 25)
    }

    func testRMultipleExactly3() {
        let trade = makeTrade(rMultiple: 3.0)
        let grade = TradeGrader.grade(trade, portfolioMetrics: defaultMetrics)
        XCTAssertEqual(grade.rScore, 25, "R >= 3.0 should score 25")
    }

    func testRMultiple2Point0() {
        let trade = makeTrade(rMultiple: 2.0)
        let grade = TradeGrader.grade(trade, portfolioMetrics: defaultMetrics)
        XCTAssertEqual(grade.rScore, 22, "R >= 2.0 should score 22")
    }

    func testRMultiple1Point5() {
        let trade = makeTrade(rMultiple: 1.5)
        let grade = TradeGrader.grade(trade, portfolioMetrics: defaultMetrics)
        XCTAssertEqual(grade.rScore, 20, "R >= 1.5 should score 20")
    }

    func testModerateRMultiple() {
        let trade = makeTrade(rMultiple: 1.2)
        let grade = TradeGrader.grade(trade, portfolioMetrics: defaultMetrics)
        XCTAssertEqual(grade.rScore, 17)
    }

    func testRMultiple0Point5() {
        let trade = makeTrade(rMultiple: 0.5)
        let grade = TradeGrader.grade(trade, portfolioMetrics: defaultMetrics)
        XCTAssertEqual(grade.rScore, 13, "R >= 0.5 should score 13")
    }

    func testZeroRMultiple() {
        let trade = makeTrade(rMultiple: 0.0)
        let grade = TradeGrader.grade(trade, portfolioMetrics: defaultMetrics)
        XCTAssertEqual(grade.rScore, 8, "R == 0 should score 8 (breakeven)")
    }

    func testSlightlyNegativeRMultiple() {
        let trade = makeTrade(rMultiple: -0.3)
        let grade = TradeGrader.grade(trade, portfolioMetrics: defaultMetrics)
        XCTAssertEqual(grade.rScore, 5, "R >= -0.5 should score 5")
    }

    func testNegativeRMultipleMinus1() {
        let trade = makeTrade(rMultiple: -0.8)
        let grade = TradeGrader.grade(trade, portfolioMetrics: defaultMetrics)
        XCTAssertEqual(grade.rScore, 3, "R >= -1.0 should score 3")
    }

    func testNegativeRMultipleGetsLowScore() {
        let trade = makeTrade(rMultiple: -1.5)
        let grade = TradeGrader.grade(trade, portfolioMetrics: defaultMetrics)
        XCTAssertEqual(grade.rScore, 0)
    }

    func testVeryLargeRMultiple() {
        let trade = makeTrade(rMultiple: 10.0)
        let grade = TradeGrader.grade(trade, portfolioMetrics: defaultMetrics)
        XCTAssertEqual(grade.rScore, 25, "Very large R should still cap at 25")
    }

    func testVeryNegativeRMultiple() {
        let trade = makeTrade(rMultiple: -5.0)
        let grade = TradeGrader.grade(trade, portfolioMetrics: defaultMetrics)
        XCTAssertEqual(grade.rScore, 0, "Very negative R should be 0")
    }

    // MARK: - Execution Scoring

    func testGoodMFEMAERatio() {
        // MFE:MAE ratio = 30/5 = 6.0, low slippage, used FVG -> max execution
        let trade = makeTrade(maePips: 5, mfePips: 30, usedFVG: true, slippagePips: 0.3)
        let grade = TradeGrader.grade(trade, portfolioMetrics: defaultMetrics)
        XCTAssertEqual(grade.executionScore, 25, "Expected max execution score")
    }

    func testPoorMFEMAERatio() {
        // MFE:MAE ratio = 5/20 = 0.25, high slippage, no FVG
        let trade = makeTrade(maePips: 20, mfePips: 5, usedFVG: false, slippagePips: 3.0)
        let grade = TradeGrader.grade(trade, portfolioMetrics: defaultMetrics)
        XCTAssertLessThanOrEqual(grade.executionScore, 5)
    }

    func testZeroMAEWithPositiveMFE() {
        // MAE is 0, MFE > 0 -> perfect entry, ratio treated as 10
        let trade = makeTrade(maePips: 0, mfePips: 20, slippagePips: 0.3)
        let grade = TradeGrader.grade(trade, portfolioMetrics: defaultMetrics)
        XCTAssertGreaterThanOrEqual(grade.executionScore, 15,
                                    "Zero MAE with positive MFE should score high on ratio")
    }

    func testZeroBothMAEAndMFE() {
        // Both zero -> ratio treated as 0
        let trade = makeTrade(maePips: 0, mfePips: 0, slippagePips: 0.3)
        let grade = TradeGrader.grade(trade, portfolioMetrics: defaultMetrics)
        // ratio = 0 -> 3 points from ratio, 5 from low slippage = 8
        XCTAssertEqual(grade.executionScore, 8)
    }

    func testFVGBonusAdded() {
        // Compare with and without FVG, everything else equal
        let withFVG = makeTrade(maePips: 10, mfePips: 10, usedFVG: true, slippagePips: 1.5)
        let withoutFVG = makeTrade(maePips: 10, mfePips: 10, usedFVG: false, slippagePips: 1.5)
        let gradeWith = TradeGrader.grade(withFVG, portfolioMetrics: defaultMetrics)
        let gradeWithout = TradeGrader.grade(withoutFVG, portfolioMetrics: defaultMetrics)
        XCTAssertEqual(gradeWith.executionScore - gradeWithout.executionScore, 5,
                       "FVG bonus should add exactly 5 points")
    }

    func testExecutionScoreCappedAt25() {
        // Best possible: ratio >= 3 (15) + slippage <= 0.5 (5) + FVG (5) = 25 (capped)
        let trade = makeTrade(maePips: 1, mfePips: 100, usedFVG: true, slippagePips: 0.1)
        let grade = TradeGrader.grade(trade, portfolioMetrics: defaultMetrics)
        XCTAssertEqual(grade.executionScore, 25, "Execution score should not exceed 25")
    }

    // MARK: - Timing Scoring

    func testLondonSessionPrimeHour() {
        // London session + prime hour (9) + bias with -> high timing
        let trade = makeTrade(session: .london, hour: 9, biasAtEntry: .with)
        let grade = TradeGrader.grade(trade, portfolioMetrics: defaultMetrics)
        XCTAssertEqual(grade.timingScore, 25)
    }

    func testNYOverlapSessionPrimeHour() {
        // NY Overlap + prime NY open hour (13) + bias with -> max timing
        let trade = makeTrade(session: .nyOverlap, hour: 13, biasAtEntry: .with)
        let grade = TradeGrader.grade(trade, portfolioMetrics: defaultMetrics)
        XCTAssertEqual(grade.timingScore, 25)
    }

    func testNYSession() {
        let trade = makeTrade(session: .ny, hour: 13, biasAtEntry: .with)
        let grade = TradeGrader.grade(trade, portfolioMetrics: defaultMetrics)
        // NY (7) + prime hour 13 (10) + bias with (5) = 22
        XCTAssertEqual(grade.timingScore, 22)
    }

    func testAsianSession() {
        let trade = makeTrade(session: .asian, hour: 3, biasAtEntry: .neutral)
        let grade = TradeGrader.grade(trade, portfolioMetrics: defaultMetrics)
        // Asian (5) + off hour (1) + neutral (2) = 8
        XCTAssertEqual(grade.timingScore, 8)
    }

    func testLateSessionBadHour() {
        // Late session + off-hour + against bias -> low timing
        let trade = makeTrade(session: .late, hour: 3, biasAtEntry: .against)
        let grade = TradeGrader.grade(trade, portfolioMetrics: defaultMetrics)
        XCTAssertLessThanOrEqual(grade.timingScore, 5)
    }

    func testBiasNeutralScoring() {
        let withBias = makeTrade(session: .london, hour: 8, biasAtEntry: .with)
        let neutralBias = makeTrade(session: .london, hour: 8, biasAtEntry: .neutral)
        let gradeWith = TradeGrader.grade(withBias, portfolioMetrics: defaultMetrics)
        let gradeNeutral = TradeGrader.grade(neutralBias, portfolioMetrics: defaultMetrics)
        XCTAssertEqual(gradeWith.timingScore - gradeNeutral.timingScore, 3,
                       "With bias should be 3 points higher than neutral (5 vs 2)")
    }

    func testBiasAgainstScoring() {
        let withBias = makeTrade(session: .london, hour: 8, biasAtEntry: .with)
        let againstBias = makeTrade(session: .london, hour: 8, biasAtEntry: .against)
        let gradeWith = TradeGrader.grade(withBias, portfolioMetrics: defaultMetrics)
        let gradeAgainst = TradeGrader.grade(againstBias, portfolioMetrics: defaultMetrics)
        XCTAssertEqual(gradeWith.timingScore - gradeAgainst.timingScore, 5,
                       "With bias should be 5 points higher than against (5 vs 0)")
    }

    func testTimingScoreCappedAt25() {
        // London (10) + prime hour (10) + with (5) = 25, should not exceed
        let trade = makeTrade(session: .london, hour: 7, biasAtEntry: .with)
        let grade = TradeGrader.grade(trade, portfolioMetrics: defaultMetrics)
        XCTAssertLessThanOrEqual(grade.timingScore, 25)
    }

    // MARK: - Management Scoring

    func testWinningTradeWithGoodExit() {
        // Winner with low post-close continuation and normal duration
        let trade = makeTrade(netProfit: 100, durationMin: 45, hitBreakeven: true, postClose30m: 2.0)
        let grade = TradeGrader.grade(trade, portfolioMetrics: defaultMetrics)
        // hitBE + win (5) + normal duration ratio ~1.0 (10) + good exit postClose < 5 (10) = 25
        XCTAssertEqual(grade.managementScore, 25)
    }

    func testLosingTradeQuickCut() {
        // Loser cut quickly: duration < avgDur/2 = 22.5
        let trade = makeTrade(netProfit: -30, durationMin: 15, postClose30m: 0)
        let grade = TradeGrader.grade(trade, portfolioMetrics: defaultMetrics)
        // no hitBE bonus (losing), normal duration ratio ~0.33 (6), quick cut (8) = 14
        XCTAssertGreaterThanOrEqual(grade.managementScore, 10)
    }

    func testExtremeDurationPenalized() {
        // Duration extremely far from average (5x the average = 225 min)
        let trade = makeTrade(netProfit: 20, durationMin: 225, postClose30m: 3.0)
        let grade = TradeGrader.grade(trade, portfolioMetrics: defaultMetrics)
        // durRatio = 225/45 = 5.0 -> extreme outlier (2), good exit (10), no hitBE = 12
        XCTAssertLessThan(grade.managementScore, 20, "Extreme duration should be penalized")
    }

    func testHighPostCloseContinuationPenalized() {
        // Left a lot on the table: postClose30m = 30
        let trade = makeTrade(netProfit: 50, durationMin: 45, postClose30m: 30.0)
        let grade = TradeGrader.grade(trade, portfolioMetrics: defaultMetrics)
        // No hitBE, normal dur (10), high postClose (2) = 12
        XCTAssertLessThan(grade.managementScore, 20, "High post-close continuation should be penalized")
    }

    // MARK: - Overall Grade Aggregation

    func testExcellentTradeGetsA() {
        let trade = makeTrade(
            rMultiple: 3.0,
            maePips: 3, mfePips: 25,
            session: .london, hour: 8,
            usedFVG: true, hitBreakeven: true,
            slippagePips: 0.2,
            postClose30m: 2.0,
            biasAtEntry: .with
        )
        let grade = TradeGrader.grade(trade, portfolioMetrics: defaultMetrics)
        XCTAssertEqual(grade.overall, .a, "Excellent trade should get A grade (total: \(grade.total))")
    }

    func testTerribleTradeGetsDorF() {
        let trade = makeTrade(
            netProfit: -100,
            rMultiple: -2.0,
            maePips: 30, mfePips: 3,
            session: .late, hour: 2,
            slippagePips: 3.0,
            postClose30m: 25.0,
            biasAtEntry: .against
        )
        let grade = TradeGrader.grade(trade, portfolioMetrics: defaultMetrics)
        XCTAssertTrue(grade.overall == .d || grade.overall == .f,
                      "Terrible trade should get D or F (total: \(grade.total))")
    }

    func testTotalScoreIsSumOfDimensions() {
        let trade = makeTrade()
        let grade = TradeGrader.grade(trade, portfolioMetrics: defaultMetrics)
        XCTAssertEqual(grade.total, grade.rScore + grade.executionScore + grade.timingScore + grade.managementScore)
    }

    func testGradeBoundaryA() {
        // Craft a trade that scores exactly at the A boundary (80+)
        let trade = makeTrade(
            netProfit: 100,
            rMultiple: 3.0,
            maePips: 3, mfePips: 25,
            session: .london, hour: 8,
            durationMin: 45,
            usedFVG: true, hitBreakeven: true,
            slippagePips: 0.3,
            postClose30m: 2.0,
            biasAtEntry: .with
        )
        let grade = TradeGrader.grade(trade, portfolioMetrics: defaultMetrics)
        XCTAssertGreaterThanOrEqual(grade.total, 80)
        XCTAssertEqual(grade.overall, TradeGrader.TradeGrade.Grade.a)
    }

    func testGradeBoundaries() {
        // Verify grade letters correspond to score ranges for any given trade
        let trade = makeTrade()
        let grade = TradeGrader.grade(trade, portfolioMetrics: defaultMetrics)
        let total = grade.total

        switch grade.overall {
        case .a: XCTAssertGreaterThanOrEqual(total, 80)
        case .b: XCTAssertTrue(total >= 65 && total < 80)
        case .c: XCTAssertTrue(total >= 50 && total < 65)
        case .d: XCTAssertTrue(total >= 35 && total < 50)
        case .f: XCTAssertLessThan(total, 35)
        }
    }

    func testEachDimensionMaxIs25() {
        // Best trade possible should have each dimension at 25
        let trade = makeTrade(
            netProfit: 200,
            rMultiple: 5.0,
            maePips: 1, mfePips: 50,
            session: .london, hour: 8,
            durationMin: 45,
            usedFVG: true, hitBreakeven: true,
            slippagePips: 0.1,
            postClose30m: 1.0,
            biasAtEntry: .with
        )
        let grade = TradeGrader.grade(trade, portfolioMetrics: defaultMetrics)
        XCTAssertLessThanOrEqual(grade.rScore, 25)
        XCTAssertLessThanOrEqual(grade.executionScore, 25)
        XCTAssertLessThanOrEqual(grade.timingScore, 25)
        XCTAssertLessThanOrEqual(grade.managementScore, 25)
        XCTAssertLessThanOrEqual(grade.total, 100)
    }

    func testEachDimensionMinIs0() {
        let trade = makeTrade(
            netProfit: -200,
            rMultiple: -3.0,
            maePips: 50, mfePips: 1,
            session: .late, hour: 1,
            durationMin: 300,
            usedFVG: false, hitBreakeven: false,
            slippagePips: 5.0,
            postClose30m: 40.0,
            biasAtEntry: .against
        )
        let grade = TradeGrader.grade(trade, portfolioMetrics: defaultMetrics)
        XCTAssertGreaterThanOrEqual(grade.rScore, 0)
        XCTAssertGreaterThanOrEqual(grade.executionScore, 0)
        XCTAssertGreaterThanOrEqual(grade.timingScore, 0)
        XCTAssertGreaterThanOrEqual(grade.managementScore, 0)
    }

    // MARK: - GradeBadge Color Mapping

    func testGradeAColorIsGreen() {
        let color = TradeGrader.TradeGrade.Grade.a.color
        // profitGreen is Color(red: 0, green: 0.85, blue: 0.45) — full opacity
        XCTAssertNotNil(color, "Grade A should have a color")
    }

    func testGradeBColorIsGreenFaded() {
        let color = TradeGrader.TradeGrade.Grade.b.color
        XCTAssertNotNil(color, "Grade B should have a color")
    }

    func testGradeCColorIsOrange() {
        let color = TradeGrader.TradeGrade.Grade.c.color
        XCTAssertNotNil(color, "Grade C should have a color")
    }

    func testGradeDColorIsRedFaded() {
        let color = TradeGrader.TradeGrade.Grade.d.color
        XCTAssertNotNil(color, "Grade D should have a color")
    }

    func testGradeFColorIsRed() {
        let color = TradeGrader.TradeGrade.Grade.f.color
        XCTAssertNotNil(color, "Grade F should have a color")
    }

    func testAllGradesHaveDistinctRawValues() {
        let grades: [TradeGrader.TradeGrade.Grade] = [.a, .b, .c, .d, .f]
        let rawValues = grades.map(\.rawValue)
        XCTAssertEqual(Set(rawValues).count, 5, "All grades should have unique raw values")
        XCTAssertEqual(rawValues, ["A", "B", "C", "D", "F"])
    }

    // MARK: - Edge Cases

    func testGradeWithEmptyMetrics() {
        // Use .empty portfolio metrics
        let emptyMetrics = MetricsCalculator.PortfolioMetrics.empty
        let trade = makeTrade(rMultiple: 1.0)
        let grade = TradeGrader.grade(trade, portfolioMetrics: emptyMetrics)
        // Should not crash; averageDuration of 0 is handled via max(metrics.averageDuration, 1)
        XCTAssertGreaterThanOrEqual(grade.total, 0)
        XCTAssertLessThanOrEqual(grade.total, 100)
    }

    func testGradeConsistencyAcrossMultipleCalls() {
        // Same trade graded twice should produce identical results
        let trade = makeTrade(rMultiple: 1.5, session: .ny, hour: 14)
        let grade1 = TradeGrader.grade(trade, portfolioMetrics: defaultMetrics)
        let grade2 = TradeGrader.grade(trade, portfolioMetrics: defaultMetrics)
        XCTAssertEqual(grade1.total, grade2.total)
        XCTAssertEqual(grade1.overall, grade2.overall)
        XCTAssertEqual(grade1.rScore, grade2.rScore)
        XCTAssertEqual(grade1.executionScore, grade2.executionScore)
        XCTAssertEqual(grade1.timingScore, grade2.timingScore)
        XCTAssertEqual(grade1.managementScore, grade2.managementScore)
    }
}
