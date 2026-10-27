import XCTest
@testable import Dojix

final class PerformanceTests: XCTestCase {

    // MARK: - Test Helpers

    private func makeRandomTrade(ticket: Int64, closeTime: Date = Date()) -> Trade {
        let symbols = ["GBPUSD", "EURUSD", "USDJPY", "AUDUSD", "GBPJPY"]
        let sessions: [TradingSession] = [.asian, .london, .nyOverlap, .ny, .late]
        let days = ["Mon", "Tue", "Wed", "Thu", "Fri"]
        let biases: [BiasAlignment] = [.with, .against, .neutral]
        let regimes: [VolatilityRegime] = [.low, .med, .high]

        let profit = Double.random(in: -200...300)
        let symbol = symbols.randomElement()!
        let session = sessions.randomElement()!
        let hour = Int.random(in: 0...23)

        return Trade(
            id: nil, ticket: ticket, symbol: symbol,
            direction: Bool.random() ? .buy : .sell,
            lots: Double.random(in: 0.01...1.0),
            openTime: closeTime.addingTimeInterval(-Double(Int.random(in: 300...7200))),
            closeTime: closeTime,
            durationMin: Int.random(in: 5...120),
            openPrice: Decimal(string: "1.25000")!,
            closePrice: Decimal(string: "1.25\(Int.random(in: 100...999))")!,
            sl: Decimal(string: "1.24800")!,
            tp: Decimal(string: "1.25500")!,
            netProfit: Decimal(floatLiteral: profit),
            maePips: Double.random(in: 0...30),
            mfePips: Double.random(in: 0...50),
            rMultiple: Double.random(in: -3...5),
            session: session,
            dayOfWeek: days.randomElement()!,
            hour: hour,
            rangeSize: Double.random(in: 20...80),
            sweepDepth: Double.random(in: 0...25),
            usedFVG: Bool.random(),
            volRegime: regimes.randomElement()!,
            hitBreakeven: Bool.random(),
            scaledIn: Bool.random(),
            magic: 12345,
            comment: "perf test",
            timeToMFEMin: Int.random(in: 5...60),
            slDistPips: Double.random(in: 10...40),
            slippagePips: Double.random(in: 0...2),
            postClose15m: Double.random(in: -10...20),
            postClose30m: Double.random(in: -15...30),
            biasAtEntry: biases.randomElement()!,
            importedAt: Date()
        )
    }

    private func generateTrades(count: Int) -> [Trade] {
        let baseDate = Date()
        return (0..<count).map { i in
            makeRandomTrade(
                ticket: Int64(i + 1),
                closeTime: baseDate.addingTimeInterval(-Double(i) * 3600)
            )
        }
    }

    // MARK: - Bulk Insert Performance

    func testBulkInsert500Trades() throws {
        let database = try DatabaseManager(inMemory: true)
        let repository = TradeRepository(database: database)
        let trades = generateTrades(count: 500)

        measure {
            try? repository.deleteAll()
            _ = try? repository.bulkInsert(trades)
        }

        XCTAssertEqual(try repository.count(), 500)
    }

    func testBulkInsert1000Trades() throws {
        let database = try DatabaseManager(inMemory: true)
        let repository = TradeRepository(database: database)
        let trades = generateTrades(count: 1000)

        measure {
            try? repository.deleteAll()
            _ = try? repository.bulkInsert(trades)
        }

        XCTAssertEqual(try repository.count(), 1000)
    }

    // MARK: - Query Performance

    func testFetchAll500Trades() throws {
        let database = try DatabaseManager(inMemory: true)
        let repository = TradeRepository(database: database)
        _ = try repository.bulkInsert(generateTrades(count: 500))

        measure {
            _ = try? repository.fetchAll()
        }
    }

    func testFetchBySymbol500Trades() throws {
        let database = try DatabaseManager(inMemory: true)
        let repository = TradeRepository(database: database)
        _ = try repository.bulkInsert(generateTrades(count: 500))

        measure {
            _ = try? repository.fetchBySymbol("GBPUSD")
        }
    }

    func testEquityCurve500Trades() throws {
        let database = try DatabaseManager(inMemory: true)
        let repository = TradeRepository(database: database)
        _ = try repository.bulkInsert(generateTrades(count: 500))

        measure {
            _ = try? repository.equityCurve()
        }
    }

    func testTotalProfit500Trades() throws {
        let database = try DatabaseManager(inMemory: true)
        let repository = TradeRepository(database: database)
        _ = try repository.bulkInsert(generateTrades(count: 500))

        measure {
            _ = try? repository.totalProfit()
        }
    }

    func testProfitBySymbol500Trades() throws {
        let database = try DatabaseManager(inMemory: true)
        let repository = TradeRepository(database: database)
        _ = try repository.bulkInsert(generateTrades(count: 500))

        measure {
            _ = try? repository.profitBySymbol()
        }
    }

    // MARK: - Metrics Calculation Performance

    func testMetricsCalculation500Trades() throws {
        let trades = generateTrades(count: 500)

        measure {
            _ = MetricsCalculator.calculate(from: trades)
        }
    }

    func testMetricsCalculation1000Trades() throws {
        let trades = generateTrades(count: 1000)

        measure {
            _ = MetricsCalculator.calculate(from: trades)
        }
    }

    func testEdgeBreakdowns500Trades() throws {
        let trades = generateTrades(count: 500)

        measure {
            _ = MetricsCalculator.edgeBySession(from: trades)
            _ = MetricsCalculator.edgeByPair(from: trades)
            _ = MetricsCalculator.edgeByHour(from: trades)
            _ = MetricsCalculator.edgeByDay(from: trades)
            _ = MetricsCalculator.edgeByBias(from: trades)
            _ = MetricsCalculator.edgeByVolRegime(from: trades)
        }
    }

    // MARK: - CSV Parser Performance

    func testParseCSV250Trades() throws {
        // Generate a CSV string with 250 trades
        var csv = "Ticket,Symbol,Direction,Lots,OpenTime,CloseTime,DurationMin,OpenPrice,ClosePrice,SL,TP,NetProfit,MAE_Pips,MFE_Pips,RMultiple,Session,DayOfWeek,Hour,RangeSize,SweepDepth,UsedFVG,VolRegime,HitBreakeven,ScaledIn,Magic,Comment,TimeToMFE_Min,SLDist_Pips,Slippage_Pips,PostClose15m,PostClose30m,BiasAtEntry\n"

        for i in 1...250 {
            let profit = Double.random(in: -200...300)
            csv += "\(i),GBPUSD,BUY,0.10,2026.01.15 08:30:00,2026.01.15 09:45:00,75,1.25000,1.25250,1.24800,1.25500,\(String(format: "%.2f", profit)),8.5,30.2,1.25,LONDON,Wed,8,45.0,12.3,YES,MED,NO,NO,12345,,35,20.0,0.5,15.0,22.0,WITH\n"
        }

        let tempFile = NSTemporaryDirectory() + "perf_test_\(UUID().uuidString).csv"
        try csv.write(toFile: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        measure {
            _ = try? CSVParser.parse(fileAt: tempFile)
        }
    }
}
