import SwiftUI

/// Institutional-level analysis of how recurring economic events impact trading performance.
/// Profiles each event type (NFP, FOMC, CPI, ECB, BOE) with timing analysis,
/// per-pair impact, and actionable trade/skip recommendations.
struct EventImpactProfiler: View {
    let trades: [Trade]

    private var results: [EventTypeResult] { analyzeByEventType(trades) }

    var body: some View {
        if trades.count < 30 {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 16) {
                header

                if results.isEmpty {
                    Text("Not enough event-day trades for analysis")
                        .font(.bodyText)
                        .foregroundStyle(Color.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: 60)
                } else {
                    eventVsQuietSummary

                    ForEach(results) { result in
                        eventTypeRow(result)
                    }

                    if results.contains(where: { !$0.preTrades.isEmpty || !$0.postTrades.isEmpty }) {
                        timingBreakdown
                    }

                    pairImpact
                    insightBanner
                }
            }
            .padding(20)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.borderCard, lineWidth: 1))
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.semanticRedDim)
                        .frame(width: 22, height: 22)
                    Image(systemName: "newspaper.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.semanticRed)
                }
                Text("Event Impact Profiler")
                    .font(.cardTitle)
            }
            Spacer()
            let eventCount = results.flatMap(\.trades).count
            ConfidenceBadge(sampleSize: eventCount, compact: true)
        }
    }

    // MARK: - Event vs Quiet Summary

    private var eventVsQuietSummary: some View {
        let allEvent = results.flatMap(\.trades)
        let eventIDs = Set(allEvent.map(\.ticket))
        let quiet = trades.filter { !eventIDs.contains($0.ticket) }

        return HStack(spacing: 12) {
            miniStatCard(
                title: "EVENT DAYS", trades: allEvent,
                color: Color.semanticAmber
            )
            miniStatCard(
                title: "QUIET DAYS", trades: quiet,
                color: Color.accent
            )
        }
    }

    // MARK: - Event Type Rows

    private func eventTypeRow(_ result: EventTypeResult) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(result.recommendation.dimColor)
                    .frame(width: 28, height: 28)
                Image(systemName: result.eventType.icon)
                    .font(.system(size: 15))
                    .foregroundStyle(result.recommendation.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(result.eventType.rawValue)
                    .font(.system(size: 15, weight: .semibold))
                Text("\(result.trades.count) trades")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(width: 100, alignment: .leading)

            Spacer()

            metricColumn(
                String(format: "%.0f%%", result.winRate * 100), label: "WR",
                color: result.winRate >= 0.5 ? Color.semanticGreen : Color.semanticRed,
                width: 40
            )
            metricColumn(
                String(format: "%+.2f", result.avgPnL), label: "Avg",
                color: Color.forPnL(result.avgPnL),
                width: 55
            )
            metricColumn(
                String(format: "%.2f", result.profitFactor), label: "PF",
                color: result.profitFactor >= 1.0 ? Color.semanticGreen : Color.semanticRed,
                width: 40
            )

            Text(result.recommendation.rawValue)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(result.recommendation.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(result.recommendation.dimColor)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            ConfidenceBadge(sampleSize: result.trades.count, compact: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.bgInset)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderCard, lineWidth: 1))
    }

    private func metricColumn(_ value: String, label: String, color: Color, width: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.monoSubtitle)
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(width: width)
    }

    // MARK: - Timing Breakdown

    private var timingBreakdown: some View {
        let allPre = results.flatMap(\.preTrades)
        let allDuring = results.flatMap(\.duringTrades)
        let allPost = results.flatMap(\.postTrades)

        return VStack(alignment: .leading, spacing: 8) {
            Text("TIMING ANALYSIS")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.textSecondary)

            HStack(spacing: 8) {
                timingCard("Pre-Event", trades: allPre, icon: "arrow.right", color: Color.semanticBlue)
                timingCard("During", trades: allDuring, icon: "bolt.fill", color: Color.semanticAmber)
                timingCard("Post-Event", trades: allPost, icon: "arrow.left", color: Color.semanticPurple)
            }
        }
    }

    private func timingCard(_ title: String, trades: [Trade], icon: String, color: Color) -> some View {
        let winRate = trades.isEmpty ? 0 : Double(trades.filter(\.isWin).count) / Double(trades.count)
        let avgPnL = trades.isEmpty ? 0 : trades.map(\.profitDouble).reduce(0, +) / Double(trades.count)

        return VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 11)).foregroundStyle(color)
                Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(Color.textSecondary)
            }

            if trades.isEmpty {
                Text("–")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.textTertiary)
                Text(" ")
                    .font(.system(size: 12, design: .monospaced))
                Text(" ")
                    .font(.system(size: 11))
            } else {
                Text(String(format: "%.0f%%", winRate * 100))
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(winRate >= 0.5 ? Color.semanticGreen : Color.semanticRed)
                Text(String(format: "%+.2f avg", avgPnL))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.forPnL(avgPnL))
                Text("\(trades.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(Color.bgInset)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderCard, lineWidth: 1))
    }

    // MARK: - Pair Impact

    @ViewBuilder
    private var pairImpact: some View {
        let allEvent = results.flatMap(\.trades)
        let eventByPair = Dictionary(grouping: allEvent, by: \.symbol)
        let overallByPair = Dictionary(grouping: trades, by: \.symbol)

        let rows: [(symbol: String, eventWR: Double, normalWR: Double, delta: Double, count: Int)] =
            eventByPair.compactMap { symbol, eventTrades in
                guard eventTrades.count >= 5 else { return nil }
                let ewr = Double(eventTrades.filter(\.isWin).count) / Double(eventTrades.count)
                let normalTrades = overallByPair[symbol] ?? []
                let nwr = normalTrades.isEmpty ? 0 : Double(normalTrades.filter(\.isWin).count) / Double(normalTrades.count)
                return (symbol, ewr, nwr, ewr - nwr, eventTrades.count)
            }
            .sorted { abs($0.delta) > abs($1.delta) }

        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("PAIR IMPACT DURING EVENTS")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.textSecondary)

                ForEach(rows.prefix(5), id: \.symbol) { row in
                    HStack {
                        Text(row.symbol)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .frame(width: 70, alignment: .leading)

                        Text(String(format: "%.0f%%", row.normalWR * 100))
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: 35)

                        Image(systemName: "arrow.right")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textTertiary)

                        Text(String(format: "%.0f%%", row.eventWR * 100))
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(row.eventWR >= 0.5 ? Color.semanticGreen : Color.semanticRed)
                            .frame(width: 35)

                        Spacer()

                        Text(String(format: "%+.0f%%", row.delta * 100))
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(row.delta >= 0 ? Color.semanticGreen : Color.semanticRed)

                        Text("(\(row.count))")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
        }
    }

    // MARK: - Insight

    private var insightBanner: some View {
        let worst = results.filter { $0.trades.count >= 5 && $0.avgPnL < 0 }
            .min(by: { $0.avgPnL < $1.avgPnL })
        let best = results.filter { $0.trades.count >= 5 && $0.avgPnL > 0 }
            .max(by: { $0.avgPnL < $1.avgPnL })

        let text: String
        if let worst = worst, worst.trades.count >= 10 {
            let months = max(1, tradingMonths)
            let monthlyCost = abs(worst.totalPnL) / Double(months)
            text = "Skipping \(worst.eventType.rawValue) could save ~$\(String(format: "%.0f", monthlyCost))/month (\(worst.trades.count) trades at $\(String(format: "%.2f", worst.avgPnL)) avg)."
        } else if let best = best {
            text = "Best event: \(best.eventType.rawValue) — \(String(format: "%.0f%%", best.winRate * 100)) WR, $\(String(format: "+%.2f", best.avgPnL)) avg per trade."
        } else {
            text = "Need more event-day trades for a recommendation. Keep trading and check back."
        }

        return HStack(spacing: 6) {
            Image(systemName: "lightbulb.fill")
                .font(.caption)
                .foregroundStyle(.yellow)
            Text(text)
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgInset)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderCard, lineWidth: 1))
    }

    // MARK: - Mini Stat Card

    private func miniStatCard(title: String, trades: [Trade], color: Color) -> some View {
        let wr = trades.isEmpty ? 0 : Double(trades.filter(\.isWin).count) / Double(trades.count)
        let avg = trades.isEmpty ? 0 : trades.map(\.profitDouble).reduce(0, +) / Double(trades.count)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.textSecondary)
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Win Rate").font(.system(size: 11)).foregroundStyle(Color.textTertiary)
                    Text(String(format: "%.0f%%", wr * 100))
                        .font(.monoSubtitle)
                        .fontWeight(.bold)
                        .foregroundStyle(wr >= 0.5 ? Color.semanticGreen : Color.semanticRed)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Avg P&L").font(.system(size: 11)).foregroundStyle(Color.textTertiary)
                    Text(String(format: "%+.2f", avg))
                        .font(.monoSubtitle)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.forPnL(avg))
                }
            }
            Text("\(trades.count) trades")
                .font(.system(size: 11))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(8)
        .background(Color.bgInset)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.borderCard, lineWidth: 1))
    }

    // MARK: - Analysis Engine

    private var tradingMonths: Int {
        guard let first = trades.min(by: { $0.openTime < $1.openTime })?.openTime else { return 1 }
        let days = Calendar.current.dateComponents([.day], from: first, to: Date()).day ?? 1
        return max(1, days / 30)
    }

    private func analyzeByEventType(_ trades: [Trade]) -> [EventTypeResult] {
        EventType.allCases.compactMap { eventType in
            let matching = trades.filter { matchesEvent($0, eventType: eventType) }
            guard matching.count >= 3 else { return nil }

            let winCount = matching.filter(\.isWin).count
            let winRate = Double(winCount) / Double(matching.count)
            let totalPnL = matching.map(\.profitDouble).reduce(0, +)
            let avgPnL = totalPnL / Double(matching.count)

            let rs = matching.filter { $0.rMultiple != 0 }
            let avgR = rs.isEmpty ? 0 : rs.map(\.rMultiple).reduce(0, +) / Double(rs.count)

            let grossWin = matching.filter(\.isWin).map(\.profitDouble).reduce(0, +)
            let grossLoss = abs(matching.filter(\.isLoss).map(\.profitDouble).reduce(0, +))
            let pf = grossLoss > 0 ? grossWin / grossLoss : (grossWin > 0 ? 99.0 : 0)

            let eventHour = eventType.typicalHourUTC
            let pre = matching.filter { $0.hour >= eventHour - 2 && $0.hour < eventHour }
            let during = matching.filter { $0.hour == eventHour || $0.hour == eventHour + 1 }
            let post = matching.filter { $0.hour > eventHour + 1 && $0.hour <= eventHour + 3 }

            let rec: Recommendation
            if matching.count >= 10 {
                if winRate >= 0.55 && pf >= 1.2 { rec = .trade }
                else if winRate < 0.40 || pf < 0.8 { rec = .avoid }
                else { rec = .caution }
            } else {
                rec = .caution
            }

            return EventTypeResult(
                eventType: eventType, trades: matching, winRate: winRate,
                avgPnL: avgPnL, avgR: avgR, totalPnL: totalPnL, profitFactor: pf,
                recommendation: rec, preTrades: pre, duringTrades: during, postTrades: post
            )
        }
        .sorted { $0.trades.count > $1.trades.count }
    }

    // MARK: - Event Matching Heuristics

    private func matchesEvent(_ trade: Trade, eventType: EventType) -> Bool {
        let cal = Calendar.current
        let c = cal.dateComponents([.weekday, .weekOfMonth, .day, .month, .hour], from: trade.openTime)
        let wd = c.weekday ?? 0, wom = c.weekOfMonth ?? 0
        let day = c.day ?? 0, month = c.month ?? 0, hour = c.hour ?? 0

        switch eventType {
        case .nfp:
            return wd == 6 && wom == 1
        case .fomc:
            return wd == 4 && [1, 3, 5, 6, 7, 9, 11, 12].contains(month) && (15...28).contains(day)
        case .cpi:
            return (wd == 3 || wd == 4) && (10...14).contains(day)
        case .ecb:
            return wd == 5 && [1, 3, 4, 6, 7, 9, 10, 12].contains(month)
                && (7...21).contains(day) && (11...15).contains(hour)
        case .boe:
            return wd == 5 && [2, 3, 5, 6, 8, 9, 11, 12].contains(month)
                && (1...14).contains(day) && (10...14).contains(hour)
        case .mondayOpen:
            return wd == 2 && hour < 9
        case .fridayClose:
            return wd == 6 && hour >= 18
        }
    }
}

// MARK: - Models

extension EventImpactProfiler {
    enum EventType: String, CaseIterable, Identifiable {
        case nfp = "NFP"
        case fomc = "FOMC"
        case cpi = "CPI"
        case ecb = "ECB"
        case boe = "BOE"
        case mondayOpen = "Mon Open"
        case fridayClose = "Fri Close"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .nfp: "person.3.fill"
            case .fomc: "building.columns.fill"
            case .cpi: "chart.line.uptrend.xyaxis"
            case .ecb: "eurosign.circle.fill"
            case .boe: "sterlingsign.circle.fill"
            case .mondayOpen: "sunrise.fill"
            case .fridayClose: "sunset.fill"
            }
        }

        /// Typical release hour in UTC
        var typicalHourUTC: Int {
            switch self {
            case .nfp: 13
            case .fomc: 19
            case .cpi: 13
            case .ecb: 12
            case .boe: 12
            case .mondayOpen: 0
            case .fridayClose: 21
            }
        }

        var affectedCurrencies: [String] {
            switch self {
            case .nfp, .fomc, .cpi: ["USD"]
            case .ecb: ["EUR"]
            case .boe: ["GBP"]
            case .mondayOpen, .fridayClose: []
            }
        }
    }

    enum Recommendation: String {
        case trade = "TRADE"
        case caution = "CAUTION"
        case avoid = "AVOID"

        var color: Color {
            switch self {
            case .trade: Color.semanticGreen
            case .caution: Color.semanticAmber
            case .avoid: Color.semanticRed
            }
        }

        var dimColor: Color {
            switch self {
            case .trade: Color.semanticGreenDim
            case .caution: Color.semanticAmberDim
            case .avoid: Color.semanticRedDim
            }
        }
    }

    struct EventTypeResult: Identifiable {
        let eventType: EventType
        let trades: [Trade]
        let winRate: Double
        let avgPnL: Double
        let avgR: Double
        let totalPnL: Double
        let profitFactor: Double
        let recommendation: Recommendation
        let preTrades: [Trade]
        let duringTrades: [Trade]
        let postTrades: [Trade]

        var id: String { eventType.rawValue }
    }
}
