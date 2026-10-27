import SwiftUI

/// Position sizing calculator based on account size, risk %, and trade history
struct PositionSizer: View {
    let trades: [Trade]
    let metrics: MetricsCalculator.PortfolioMetrics

    @State private var accountBalance: String = "10000"
    @State private var riskPercent: Double = 1.0

    private var balance: Double {
        Double(accountBalance) ?? 10_000
    }

    private var riskPerTrade: Double {
        balance * (riskPercent / 100)
    }

    private var avgSLPips: Double {
        let slDistances = trades.compactMap { trade -> Double? in
            guard trade.slDistPips > 0 else { return nil }
            return trade.slDistPips
        }
        guard !slDistances.isEmpty else { return 20 }
        return slDistances.reduce(0, +) / Double(slDistances.count)
    }

    /// Approximate pip value for major pairs at 0.01 lot
    private let pipValuePerMicroLot = 0.10

    private var suggestedLots: Double {
        guard avgSLPips > 0 else { return 0.01 }
        let pipValue = pipValuePerMicroLot * 100 // per standard lot
        let lots = riskPerTrade / (avgSLPips * pipValue)
        return (lots * 100).rounded() / 100 // round to 0.01
    }

    private var currentAvgLots: Double {
        guard !trades.isEmpty else { return 0 }
        return trades.map(\.lots).reduce(0, +) / Double(trades.count)
    }

    private var isSizingAligned: Bool {
        guard currentAvgLots > 0 else { return true }
        let ratio = suggestedLots / currentAvgLots
        return ratio >= 0.5 && ratio <= 2.0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Position Sizer", systemImage: "scalemass")
                .font(.headline)

            // Inputs
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Account Balance")
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                    TextField("Balance", text: $accountBalance)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .font(.monoSubtitle)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Risk per Trade")
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                    HStack(spacing: 4) {
                        Slider(value: $riskPercent, in: 0.25...5.0, step: 0.25)
                            .frame(width: 100)
                        Text(String(format: "%.2f%%", riskPercent))
                            .font(.monoSubtitle)
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: 45)
                    }
                }
            }

            Divider()

            // Results
            HStack(spacing: 24) {
                resultColumn(label: "Risk/Trade", value: riskPerTrade.asCurrency)
                resultColumn(label: "Avg SL", value: String(format: "%.1f pips", avgSLPips))
                resultColumn(label: "Suggested Lots", value: String(format: "%.2f", suggestedLots), highlight: true)
                resultColumn(label: "Current Avg", value: String(format: "%.2f", currentAvgLots))
            }

            // Alignment check
            if !trades.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: isSizingAligned ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(isSizingAligned ? Color.semanticGreen : .orange)
                        .font(.smallText)
                    Text(isSizingAligned
                        ? "Your current sizing aligns with your risk parameters."
                        : "Your current avg lot size differs significantly from the suggested size. Consider adjusting.")
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .padding(16)
    }

    private func resultColumn(label: String, value: String, highlight: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.monoSubtitle)
                .fontWeight(highlight ? .bold : .medium)
                .foregroundStyle(highlight ? Color.accent : .primary)
            Text(label)
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
        }
    }
}
