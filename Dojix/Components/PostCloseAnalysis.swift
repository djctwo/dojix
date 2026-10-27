import SwiftUI
import Charts

/// Analyzes how much price moved after trade close — identifies early exits
struct PostCloseAnalysis: View {
    let trades: [Trade]

    private var avgPostClose15m: Double {
        guard !trades.isEmpty else { return 0 }
        return trades.map(\.postClose15m).reduce(0, +) / Double(trades.count)
    }

    private var avgPostClose30m: Double {
        guard !trades.isEmpty else { return 0 }
        return trades.map(\.postClose30m).reduce(0, +) / Double(trades.count)
    }

    private var earlyExitCount: Int {
        // Trades where post-close continuation > actual MFE captured (left money on table)
        trades.filter { $0.postClose30m > 10 && $0.isWin }.count
    }

    private var earlyExitPercent: Double {
        let wins = trades.filter(\.isWin)
        guard !wins.isEmpty else { return 0 }
        let early = wins.filter { $0.postClose30m > 10 }.count
        return Double(early) / Double(wins.count) * 100
    }

    private struct ContinuationData: Identifiable {
        let id = UUID()
        let label: String
        let timeframe: String
        let avgPips: Double
    }

    private var winContinuation: [ContinuationData] {
        let wins = trades.filter(\.isWin)
        guard !wins.isEmpty else { return [] }
        let avg15 = wins.map(\.postClose15m).reduce(0, +) / Double(wins.count)
        let avg30 = wins.map(\.postClose30m).reduce(0, +) / Double(wins.count)
        return [
            ContinuationData(label: "Winners", timeframe: "15m", avgPips: avg15),
            ContinuationData(label: "Winners", timeframe: "30m", avgPips: avg30),
        ]
    }

    private var lossContinuation: [ContinuationData] {
        let losses = trades.filter(\.isLoss)
        guard !losses.isEmpty else { return [] }
        let avg15 = losses.map(\.postClose15m).reduce(0, +) / Double(losses.count)
        let avg30 = losses.map(\.postClose30m).reduce(0, +) / Double(losses.count)
        return [
            ContinuationData(label: "Losers", timeframe: "15m", avgPips: avg15),
            ContinuationData(label: "Losers", timeframe: "30m", avgPips: avg30),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Post-Close Continuation")
                .font(.headline)

            if trades.isEmpty {
                Text("No trades yet")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                // Chart showing post-close continuation for wins vs losses
                let allData = winContinuation + lossContinuation
                Chart(allData) { item in
                    BarMark(
                        x: .value("Timeframe", item.timeframe),
                        y: .value("Avg Pips", item.avgPips)
                    )
                    .foregroundStyle(by: .value("Type", item.label))
                    .position(by: .value("Type", item.label))
                }
                .chartForegroundStyleScale([
                    "Winners": Color.semanticGreen,
                    "Losers": Color.semanticRed,
                ])
                .frame(height: 140)

                // Summary metrics
                HStack(spacing: 16) {
                    VStack(spacing: 2) {
                        Text(String(format: "%.1f", avgPostClose15m))
                            .font(.monoSubtitle)
                            .fontWeight(.medium)
                        Text("Avg 15m (pips)")
                            .font(.smallText)
                            .foregroundStyle(Color.textSecondary)
                    }

                    VStack(spacing: 2) {
                        Text(String(format: "%.1f", avgPostClose30m))
                            .font(.monoSubtitle)
                            .fontWeight(.medium)
                        Text("Avg 30m (pips)")
                            .font(.smallText)
                            .foregroundStyle(Color.textSecondary)
                    }

                    VStack(spacing: 2) {
                        Text(String(format: "%.0f%%", earlyExitPercent))
                            .font(.monoSubtitle)
                            .fontWeight(.medium)
                            .foregroundStyle(earlyExitPercent > 40 ? Color.orange : Color.semanticGreen)
                        Text("Early exits")
                            .font(.smallText)
                            .foregroundStyle(Color.textSecondary)
                    }

                    Spacer()
                }

                // Insight
                if earlyExitPercent > 40 {
                    HStack(spacing: 4) {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text("Consider trailing stops — \(String(format: "%.0f", earlyExitPercent))% of wins had 10+ pips continuation")
                            .font(.smallText)
                            .foregroundStyle(Color.textSecondary)
                    }
                } else if avgPostClose30m < 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(Color.semanticGreen)
                        Text("Good exit timing — price reverses after your exits on average")
                            .font(.smallText)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay(
        RoundedRectangle(cornerRadius: 12)
            .stroke(Color.borderCard, lineWidth: 1)
    )
    }
}
