import SwiftUI

/// Detects destructive trading patterns: overtrading, revenge trading,
/// tilt, and lot size escalation after losses
struct BehavioralAnalytics: View {
    let trades: [Trade]

    // MARK: - Analysis Engine

    struct BehaviorReport {
        let disciplineScore: Int           // 0-100
        let grade: String                  // A-F
        let overtradingDays: Int           // Days where count > 2× average
        let overtradingDaysPnL: Double     // Total P&L on those days
        let revengeTrades: Int             // Re-entry within 10 min after loss
        let revengeWinRate: Double         // Win rate on revenge trades
        let revengePnL: Double             // Total P&L on revenge trades
        let tiltEvents: Int               // 3+ losses within 60 min
        let sizeEscalation: Double         // Avg lot increase after loss vs after win (ratio)
        let avgDailyTrades: Double
        let dimensions: [Dimension]
    }

    struct Dimension: Identifiable {
        let id = UUID()
        let name: String
        let score: Int    // 0-100
        let detail: String
        let icon: String
    }

    /// The analysis (internal for tests).
    var report: BehaviorReport? {
        let sorted = trades.sorted { $0.closeTime < $1.closeTime }
        guard sorted.count >= 15 else { return nil }

        // Group trades by calendar day
        let calendar = Calendar.current
        var dailyCounts: [DateComponents: [Trade]] = [:]
        for trade in sorted {
            let day = calendar.dateComponents([.year, .month, .day], from: trade.closeTime)
            dailyCounts[day, default: []].append(trade)
        }

        let tradingDays = dailyCounts.count
        let avgDaily = Double(sorted.count) / max(Double(tradingDays), 1)

        // 1. Overtrading: days with > 2× average daily trades
        let overtradingThreshold = max(avgDaily * 2, 5)
        var otDays = 0
        var otPnL = 0.0
        for (_, dayTrades) in dailyCounts {
            if Double(dayTrades.count) > overtradingThreshold {
                otDays += 1
                otPnL += dayTrades.map(\.profitDouble).reduce(0, +)
            }
        }

        // 2. Revenge trading: re-entry within 10 minutes after a loss
        var revengeTrades = 0
        var revengeWins = 0
        var revengePnL = 0.0
        for i in 1..<sorted.count {
            let prev = sorted[i - 1]
            let curr = sorted[i]
            guard prev.isLoss else { continue }
            let gap = curr.openTime.timeIntervalSince(prev.closeTime)
            if gap >= 0 && gap <= 600 { // Within 10 minutes
                revengeTrades += 1
                revengePnL += curr.profitDouble
                if curr.isWin { revengeWins += 1 }
            }
        }
        let revengeWR = revengeTrades > 0 ? Double(revengeWins) / Double(revengeTrades) : 0

        // 3. Tilt detection: 3+ losses within a 60-minute window
        var tiltEvents = 0
        for i in 0..<sorted.count {
            guard sorted[i].isLoss else { continue }
            let windowEnd = sorted[i].closeTime.addingTimeInterval(3600)
            var lossesInWindow = 1
            for j in (i + 1)..<sorted.count {
                guard sorted[j].closeTime <= windowEnd else { break }
                if sorted[j].isLoss { lossesInWindow += 1 }
            }
            if lossesInWindow >= 3 { tiltEvents += 1 }
        }
        // Deduplicate overlapping windows — rough estimate
        tiltEvents = min(tiltEvents, sorted.count / 5)

        // 4. Size escalation: average lot size after loss vs after win
        var lotsAfterWin: [Double] = []
        var lotsAfterLoss: [Double] = []
        for i in 1..<sorted.count {
            if sorted[i - 1].isWin {
                lotsAfterWin.append(sorted[i].lots)
            } else {
                lotsAfterLoss.append(sorted[i].lots)
            }
        }
        let avgAfterWin = lotsAfterWin.isEmpty ? 1 : lotsAfterWin.reduce(0, +) / Double(lotsAfterWin.count)
        let avgAfterLoss = lotsAfterLoss.isEmpty ? 1 : lotsAfterLoss.reduce(0, +) / Double(lotsAfterLoss.count)
        let sizeRatio = avgAfterWin > 0 ? avgAfterLoss / avgAfterWin : 1.0

        // Score each dimension (0-100, higher = more disciplined)
        let otScore = max(0, 100 - otDays * 25)
        let revengeScore: Int
        if revengeTrades == 0 {
            revengeScore = 100
        } else {
            let revengePct = Double(revengeTrades) / Double(sorted.count) * 100
            revengeScore = max(0, Int(saturating: 100 - revengePct * 10))
        }
        let tiltScore = max(0, 100 - tiltEvents * 20)
        let sizeScore: Int
        if sizeRatio <= 1.05 {
            sizeScore = 100
        } else if sizeRatio <= 1.2 {
            sizeScore = 75
        } else if sizeRatio <= 1.5 {
            sizeScore = 50
        } else {
            sizeScore = max(0, Int(saturating: 100 - (sizeRatio - 1) * 80))
        }

        let dimensions = [
            Dimension(
                name: "Overtrading",
                score: otScore,
                detail: otDays == 0 ? "No overtrading days detected" : "\(otDays) day\(otDays == 1 ? "" : "s") with 2× avg volume (\(otPnL.asCurrency) P&L)",
                icon: "speedometer"
            ),
            Dimension(
                name: "Revenge",
                score: revengeScore,
                detail: revengeTrades == 0 ? "No revenge trades detected" : "\(revengeTrades) trades within 10m of a loss (\(Int(saturating: revengeWR * 100))% WR, \(revengePnL.asCurrency))",
                icon: "flame"
            ),
            Dimension(
                name: "Tilt Control",
                score: tiltScore,
                detail: tiltEvents == 0 ? "No tilt episodes detected" : "\(tiltEvents) tilt event\(tiltEvents == 1 ? "" : "s") (3+ losses in 1hr)",
                icon: "brain.head.profile"
            ),
            Dimension(
                name: "Size Discipline",
                score: sizeScore,
                detail: sizeRatio <= 1.1 ? "Consistent lot sizing after wins and losses" : "Lots \(String(format: "%.0f%%", (sizeRatio - 1) * 100)) larger after losses — emotional sizing",
                icon: "scalemass"
            ),
        ]

        let overall = dimensions.map(\.score).saturatingSum() / dimensions.count
        let grade: String
        if overall >= 85 { grade = "A" }
        else if overall >= 70 { grade = "B" }
        else if overall >= 55 { grade = "C" }
        else if overall >= 40 { grade = "D" }
        else { grade = "F" }

        return BehaviorReport(
            disciplineScore: overall,
            grade: grade,
            overtradingDays: otDays,
            overtradingDaysPnL: otPnL,
            revengeTrades: revengeTrades,
            revengeWinRate: revengeWR,
            revengePnL: revengePnL,
            tiltEvents: tiltEvents,
            sizeEscalation: sizeRatio,
            avgDailyTrades: avgDaily,
            dimensions: dimensions
        )
    }

    // MARK: - View

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Discipline Score", systemImage: "brain.head.profile")
                .font(.headline)

            if let report {
                HStack(spacing: 16) {
                    // Grade circle
                    ZStack {
                        Circle()
                            .stroke(gradeColor(report.grade).opacity(0.2), lineWidth: 6)
                        Circle()
                            .trim(from: 0, to: Double(report.disciplineScore) / 100)
                            .stroke(gradeColor(report.grade), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text(report.grade)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(gradeColor(report.grade))
                            Text("\(report.disciplineScore)")
                                .font(.monoSubtitle)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    .frame(width: 64, height: 64)

                    // Dimension bars
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(report.dimensions) { dim in
                            HStack(spacing: 6) {
                                Image(systemName: dim.icon)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.textSecondary)
                                    .frame(width: 12)
                                Text(dim.name)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.textSecondary)
                                    .frame(width: 65, alignment: .trailing)
                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.secondary.opacity(0.1))
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(barColor(dim.score))
                                            .frame(width: max(2, geometry.size.width * Double(dim.score) / 100))
                                    }
                                }
                                .frame(height: 8)
                                Text("\(dim.score)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Color.textSecondary)
                                    .frame(width: 20)
                            }
                        }
                    }
                }

                // Worst dimension detail
                if let worst = report.dimensions.min(by: { $0.score < $1.score }), worst.score < 70 {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text(worst.detail)
                            .font(.smallText)
                            .foregroundStyle(Color.textSecondary)
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(Color.semanticGreen)
                        Text("Strong discipline — no destructive patterns detected")
                            .font(.smallText)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            } else {
                Text("Need at least 15 trades for behavioral analysis")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            }
        }
        .padding(16)
    }

    private func gradeColor(_ grade: String) -> Color {
        switch grade {
        case "A": Color.semanticGreen
        case "B": Color.semanticGreen.opacity(0.7)
        case "C": .orange
        case "D": Color.semanticRed.opacity(0.7)
        default: Color.semanticRed
        }
    }

    private func barColor(_ score: Int) -> Color {
        if score >= 70 { return Color.semanticGreen }
        if score >= 50 { return .orange }
        return Color.semanticRed
    }
}
