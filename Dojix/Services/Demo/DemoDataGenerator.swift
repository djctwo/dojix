import Foundation

/// Generates fictional sample trades so new users can explore the app
/// (Settings > Data > Load Sample Trades). 30 made-up trades across 5 pairs,
/// mixed sessions, 60% win rate. They are not anyone's real results.
enum DemoDataGenerator {
    /// Comment stored on every sample trade (used to find and remove them)
    static let sampleComment = "Sample (fictional)"

    /// Sample tickets start here — far above real broker ticket ranges
    static let ticketBase: Int64 = 9_000_000_000_000

    static func generateTrades() -> [Trade] {
        let now = Date()
        let calendar = Calendar.current

        // Trade templates: (symbol, direction, lots, profit, rMultiple, session, hour, durationMin, maePips, mfePips, slDistPips, volRegime, biasAtEntry)
        let templates: [(String, TradeDirection, Double, Decimal, Double, TradingSession, Int, Int, Double, Double, Double, VolatilityRegime, BiasAlignment)] = [
            // Week 1 — London focus, GBPUSD
            ("GBPUSD", .buy,  0.50, 85,   1.7, .london,    8,  42, 12.0, 28.0, 16.5, .med,  .with),
            ("EURUSD", .sell, 0.30, -45,  -0.9, .london,    9,  28, 22.0, 10.0, 15.0, .med,  .against),
            ("GBPUSD", .sell, 0.50, 120,   2.4, .london,   10,  55, 8.0,  38.0, 16.5, .high, .with),
            ("USDJPY", .buy,  0.40, -60,  -1.2, .asian,     3,  35, 25.0, 8.0,  14.0, .low,  .neutral),
            ("AUDUSD", .buy,  0.25, 35,    1.0, .asian,     4,  20, 10.0, 18.0, 12.0, .low,  .with),
            ("GBPJPY", .sell, 0.35, 95,    1.9, .nyOverlap, 13, 48, 15.0, 32.0, 18.0, .high, .with),
            // Week 2 — NY overlap edge
            ("EURUSD", .buy,  0.30, 55,    1.1, .nyOverlap, 14, 30, 14.0, 22.0, 15.0, .med,  .with),
            ("GBPUSD", .sell, 0.50, -75,  -1.5, .ny,        16, 40, 30.0, 12.0, 16.5, .med,  .against),
            ("USDJPY", .sell, 0.40, 70,    1.4, .ny,        15, 25, 10.0, 24.0, 14.0, .med,  .with),
            ("GBPJPY", .buy,  0.35, -50,  -1.0, .london,     7, 32, 20.0, 10.0, 18.0, .med,  .neutral),
            ("AUDUSD", .sell, 0.25, 40,    1.1, .asian,      2, 18, 8.0,  16.0, 12.0, .low,  .with),
            ("GBPUSD", .buy,  0.50, 150,   3.0, .london,    11, 65, 6.0,  45.0, 16.5, .high, .with),
            // Week 3 — streak building
            ("EURUSD", .sell, 0.30, 65,    1.3, .nyOverlap, 13, 38, 12.0, 25.0, 15.0, .med,  .with),
            ("GBPUSD", .buy,  0.50, 90,    1.8, .london,     9, 50, 10.0, 30.0, 16.5, .med,  .with),
            ("USDJPY", .buy,  0.40, 45,    0.9, .asian,      5, 22, 15.0, 20.0, 14.0, .low,  .neutral),
            ("GBPJPY", .sell, 0.35, -85,  -1.7, .ny,        17, 55, 35.0, 8.0,  18.0, .high, .against),
            ("AUDUSD", .buy,  0.25, 30,    0.8, .asian,      1, 15, 8.0,  14.0, 12.0, .low,  .with),
            ("GBPUSD", .sell, 0.50, -40,  -0.8, .nyOverlap, 12, 28, 18.0, 10.0, 16.5, .med,  .against),
            // Week 4 — mixed, closing out month
            ("EURUSD", .buy,  0.30, 75,    1.5, .london,    10, 45, 10.0, 28.0, 15.0, .med,  .with),
            ("GBPUSD", .buy,  0.50, 110,   2.2, .london,     8, 58, 8.0,  35.0, 16.5, .high, .with),
            ("USDJPY", .sell, 0.40, -55,  -1.1, .ny,        18, 30, 22.0, 10.0, 14.0, .low,  .against),
            ("GBPJPY", .buy,  0.35, 80,    1.6, .nyOverlap, 14, 42, 12.0, 28.0, 18.0, .med,  .with),
            ("AUDUSD", .sell, 0.25, -35,  -1.0, .london,     7, 25, 16.0, 8.0,  12.0, .med,  .neutral),
            ("EURUSD", .sell, 0.30, 50,    1.0, .ny,        16, 35, 14.0, 20.0, 15.0, .med,  .with),
            ("GBPUSD", .sell, 0.50, 130,   2.6, .london,    11, 70, 5.0,  42.0, 16.5, .high, .with),
            ("USDJPY", .buy,  0.40, 60,    1.2, .asian,      4, 28, 10.0, 22.0, 14.0, .low,  .with),
            ("GBPJPY", .sell, 0.35, -70,  -1.4, .london,     9, 38, 28.0, 10.0, 18.0, .med,  .against),
            ("AUDUSD", .buy,  0.25, 25,    0.7, .asian,      3, 12, 6.0,  12.0, 12.0, .low,  .with),
            ("GBPUSD", .buy,  0.50, -90,  -1.8, .ny,        19, 45, 32.0, 8.0,  16.5, .high, .against),
            ("EURUSD", .buy,  0.30, 40,    0.8, .london,     8, 22, 12.0, 18.0, 15.0, .med,  .with),
        ]

        let dayOfWeekNames = ["Mon", "Tue", "Wed", "Thu", "Fri"]

        var trades: [Trade] = []

        for (index, t) in templates.enumerated() {
            // Spread trades across last 28 days, 1-2 per day
            let daysBack = 28 - (index * 28 / templates.count)
            let tradeDate = calendar.date(byAdding: .day, value: -daysBack, to: now)!

            // Set hour from template
            var components = calendar.dateComponents([.year, .month, .day], from: tradeDate)
            components.hour = t.6
            components.minute = Int.random(in: 5...55)
            let openTime = calendar.date(from: components)!
            let closeTime = calendar.date(byAdding: .minute, value: t.7, to: openTime)!

            let weekday = calendar.component(.weekday, from: openTime)
            // Map: 1=Sun→Fri, 2=Mon, 3=Tue, 4=Wed, 5=Thu, 6=Fri, 7=Sat→Fri
            let dayIndex: Int
            if weekday == 1 || weekday == 7 {
                dayIndex = 4 // Map weekend to Fri
            } else {
                dayIndex = weekday - 2
            }
            let dayName = dayOfWeekNames[dayIndex]

            // Generate realistic prices based on pair
            let openPrice: Decimal
            let pipSize: Decimal
            switch t.0 {
            case "GBPUSD": openPrice = 1.26500; pipSize = 0.00010
            case "EURUSD": openPrice = 1.08500; pipSize = 0.00010
            case "USDJPY": openPrice = 149.500; pipSize = 0.010
            case "AUDUSD": openPrice = 0.65800; pipSize = 0.00010
            case "GBPJPY": openPrice = 189.500; pipSize = 0.010
            default:       openPrice = 1.00000; pipSize = 0.00010
            }

            // Approximate close price from profit and lots (about $10 per pip per standard lot)
            let profitDouble = NSDecimalNumber(decimal: t.3).doubleValue
            let pipsGained = profitDouble / (10.0 * t.2)
            let sign: Decimal = t.1 == .buy ? 1 : -1
            let closePrice = openPrice + sign * Decimal(pipsGained) * pipSize

            let trade = Trade(
                id: nil,
                ticket: ticketBase + Int64(index),
                symbol: t.0,
                direction: t.1,
                lots: t.2,
                openTime: openTime,
                closeTime: closeTime,
                durationMin: t.7,
                openPrice: openPrice,
                closePrice: closePrice,
                sl: t.1 == .buy ? openPrice - Decimal(t.10) * pipSize : openPrice + Decimal(t.10) * pipSize,
                tp: t.1 == .buy ? openPrice + Decimal(t.9) * pipSize * 2 : openPrice - Decimal(t.9) * pipSize * 2,
                netProfit: t.3,
                maePips: t.8,
                mfePips: t.9,
                rMultiple: t.4,
                session: t.5,
                dayOfWeek: dayName,
                hour: t.6,
                rangeSize: Double.random(in: 40...120),
                sweepDepth: Double.random(in: 0...15),
                usedFVG: Bool.random(),
                volRegime: t.11,
                hitBreakeven: t.3 > 0 && Bool.random(),
                scaledIn: false,
                magic: 12345,
                comment: sampleComment,
                timeToMFEMin: Int(saturating: Double(t.7) * Double.random(in: 0.3...0.8)),
                slDistPips: t.10,
                slippagePips: Double.random(in: 0.1...1.5),
                postClose15m: t.3 > 0 ? Double.random(in: -5...15) : Double.random(in: -10...5),
                postClose30m: t.3 > 0 ? Double.random(in: -8...20) : Double.random(in: -15...8),
                biasAtEntry: t.12,
                notes: "",
                tags: "",
                importedAt: now
            )

            trades.append(trade)
        }

        return trades
    }
}
