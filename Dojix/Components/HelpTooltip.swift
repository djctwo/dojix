import SwiftUI

/// Inline help tooltip — explains trading jargon with a "?" button
/// Used in journal headers, dashboard labels, and performance strips
/// More visible in beginner mode so new users can discover contextual help
struct HelpTooltip: View {
    let term: String
    let definition: String
    @State private var isShowing = false
    @AppStorage("dashboard_beginner_mode") private var isBeginnerMode = false

    var body: some View {
        Button {
            isShowing.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: isBeginnerMode ? 12 : 11))
                .foregroundStyle(isBeginnerMode ? Color.textTertiary : Color.textTertiary.opacity(0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Help: \(term)")
        .accessibilityHint(definition)
        .popover(isPresented: $isShowing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(term)
                    .font(.smallText)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.accent)
                Text(definition)
                    .font(.smallText)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: 300)
        }
    }
}

// MARK: - Common Trading Term Definitions

enum TradingTerms {
    static let rMultiple = "Your profit as a multiple of your initial risk (stop loss distance). 2R means you made 2x what you risked. Helps compare trades regardless of lot size."
    static let profitFactor = "Gross profit divided by gross loss. Above 1.0 means profitable overall. Above 1.5 is strong. Below 1.0 means you're losing money."
    static let expectancy = "How much you expect to make per trade on average: (Win% x Avg Win) - (Loss% x Avg Loss). Positive means you have a statistical edge."
    static let winRate = "Percentage of trades that closed in profit. Important but incomplete — a 40% win rate with large R-multiples can be more profitable than 70% with small wins."
    static let session = "Forex markets trade in time windows: Asian (Tokyo, 00-09 UTC), London (07-16 UTC), New York (12-21 UTC). Each has different volatility and behavior."
    static let grade = "Automatic A-F score based on: R-multiple quality (did you let winners run?), execution (entry precision), timing (session quality), and trade management (breakeven, exits)."
    static let mae = "Maximum Adverse Excursion — the worst drawdown during a trade before it closed. Shows how much heat you took. Lower is better."
    static let mfe = "Maximum Favorable Excursion — the best unrealized profit during a trade. If MFE is much higher than actual profit, you're exiting too early."
    static let sharpe = "Risk-adjusted return. Measures consistency: high Sharpe means steady gains, low means volatile. Above 1.0 is good, above 2.0 is excellent."
    static let maxDrawdown = "The largest peak-to-trough decline in your equity curve. If your account grew to $10K then dropped to $8K, max drawdown is $2K (20%)."
    static let avgR = "Your average R-multiple across all trades. Above 0.5R is strong — it means on average you make half your risk per trade."
    static let streak = "Your current consecutive winning or losing streak. A positive number means consecutive wins, negative means consecutive losses."
    static let killZone = "ICT concept: specific high-probability time windows within a session where institutional order flow creates tradeable setups."
    static let biasAlignment = "Whether your trade direction matched the higher timeframe trend. Trading with the trend generally improves win rate."
    static let volatilityRegime = "Market conditions categorized as LOW, MEDIUM, or HIGH based on average range. Your edge may work better in specific regimes."
    static let cumulativePnL = "Running total of your profit and loss across all trades in chronological order. Shows whether your account is growing or shrinking over time."
    static let lots = "Position size in standard lots. 1 standard lot = 100,000 units of the base currency. Mini lot = 0.10, micro lot = 0.01."
    static let pnl = "Profit and loss for this trade after commissions and fees. Green = profit, red = loss."
}
