import SwiftUI

// MARK: - Metrics Explained

struct HelpMetrics: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Trading Metrics Explained")
            HelpParagraph("Dojix calculates these metrics from your trade history. Understanding them is key to improving your trading.")

            HelpSubtitle("Core Metrics")
            HelpDefinition(term: "Win Rate", definition: "Percentage of trades that are profitable. A 60% win rate means 6 out of 10 trades are winners. Win rate alone doesn't determine profitability — a 40% win rate with large winners and small losers can be highly profitable.")
            HelpDefinition(term: "Profit Factor", definition: "Gross profit divided by gross loss. A PF of 2.0 means you make $2 for every $1 you lose. Above 1.0 = profitable. Above 1.5 = good. Above 2.0 = excellent. Below 1.0 = losing money.")
            HelpDefinition(term: "Expectancy", definition: "The average amount you expect to make per trade: (Win% x Avg Win) - (Loss% x Avg Loss). Positive expectancy means your system is profitable over time. This is the single most important metric.")
            HelpDefinition(term: "R-Multiple", definition: "Profit or loss expressed as a multiple of your initial risk (distance to stop loss). A 2R trade means you made 2x your risk. A -1R trade means you lost exactly your risk. Thinking in R standardizes comparison across different position sizes.")

            HelpSubtitle("Risk Metrics")
            HelpDefinition(term: "Max Drawdown", definition: "The largest peak-to-trough decline in your equity curve. If your account went from $10,000 to $8,500 before recovering, your max drawdown is $1,500 (15%). Lower is better — professional traders target max drawdown under 10%.")
            HelpDefinition(term: "Sharpe Ratio", definition: "Risk-adjusted return: average return divided by standard deviation of returns. Higher = better risk-adjusted performance. Above 1.0 is good, above 2.0 is excellent.")
            HelpDefinition(term: "Calmar Ratio", definition: "Annualized return divided by max drawdown. Measures return per unit of drawdown risk. Higher is better — shows how much return you get for the pain of drawdowns.")
            HelpDefinition(term: "Risk of Ruin", definition: "Probability of losing your account given your current win rate, reward-to-risk ratio, and position sizing. Uses the Kelly Criterion to determine optimal bet size.")

            HelpSubtitle("Trade Quality Metrics")
            HelpDefinition(term: "MAE (Maximum Adverse Excursion)", definition: "The worst drawdown during a trade before it closed. High MAE relative to profit means your entries are poor — price moves against you significantly before going your way.")
            HelpDefinition(term: "MFE (Maximum Favorable Excursion)", definition: "The best unrealized profit during a trade before it closed. If MFE is much higher than your actual profit, you're giving back too much — your exits may be too late or your stops too loose.")
            HelpDefinition(term: "Post-Close Continuation", definition: "How far price moved in your trade's direction after you exited (measured at 15m and 30m). Large continuation means you're exiting too early and leaving money on the table.")

            HelpSubtitle("Trade Grade (A-F)")
            HelpParagraph("Each trade is automatically scored on 4 dimensions (25 points each, 100 total):")
            HelpBullet("R-Multiple Quality: Higher R = better score. 3R+ = perfect, negative R = zero.")
            HelpBullet("Execution Efficiency: MFE-to-MAE ratio — how well you entered relative to the move.")
            HelpBullet("Timing Discipline: Session quality (London/NY overlap best), prime hours, bias alignment.")
            HelpBullet("Trade Management: Breakeven usage, duration normalcy, post-close capture.")
            HelpParagraph("Grades: A (80+), B (65+), C (50+), D (35+), F (<35).")
        }
    }
}

// MARK: - Analytics Components

struct HelpAnalyticsComponents: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Dashboard Analytics Components")
            HelpParagraph("The Dashboard includes 66 analytics components across 6 tabs: Timing, Sessions, Pairs, Risk, Behavioral, and Advanced. Here's what each one measures and why it matters.")

            HelpSubtitle("Performance & Equity")
            HelpDefinition(term: "Performance Summary", definition: "Weekly, monthly, and last-month cards with mini daily P&L bars. Spot trends in your recent performance at a glance.")
            HelpDefinition(term: "Period Comparison", definition: "Side-by-side current vs previous period metrics. See if you're improving or declining.")
            HelpDefinition(term: "Equity Curve", definition: "Cumulative P&L over time. A smooth upward curve = consistent edge. Choppy or declining = problems.")
            HelpDefinition(term: "Drawdown Chart", definition: "Shows underwater equity periods. Visualizes how deep and long your drawdowns are.")
            HelpDefinition(term: "Expectancy Curve", definition: "Actual P&L trajectory vs expected (based on your expectancy). Tells you if live results match your system's theoretical edge.")
            HelpDefinition(term: "Growth Projection", definition: "Forward-looking projections (3/6/12 months) with confidence bands. Sets realistic account growth expectations.")
            HelpDefinition(term: "Monthly Returns", definition: "Month-by-year P&L table. Best and worst months highlighted. Standard in professional fund reporting.")
            HelpDefinition(term: "Weekly Heatmap", definition: "Color-coded weekly P&L grid. Tracks week-to-week consistency and winning/losing streaks.")

            HelpSubtitle("Edge & Timing")
            HelpDefinition(term: "Session Heatmap", definition: "P&L by session type with color intensity. Shows which sessions produce your edge.")
            HelpDefinition(term: "Hourly P&L Chart", definition: "Bar chart of P&L by UTC hour with session overlay labels. Pinpoints your most and least profitable hours.")
            HelpDefinition(term: "Day of Week Chart", definition: "P&L by weekday. Identifies if certain days are consistently profitable or not.")
            HelpDefinition(term: "Trade Time Heatmap", definition: "2D heatmap: hour x day of week. Finds specific time slots that produce edge (e.g., London open on Tuesdays).")
            HelpDefinition(term: "Session Intelligence", definition: "Per-session recommendation: FOCUS, OK, REDUCE, or AVOID. Data-driven session selection based on your performance.")
            HelpDefinition(term: "Directional Edge", definition: "Compares long vs short P&L. Reveals if you have a directional bias that works (or doesn't).")

            HelpSubtitle("Risk & Behavior")
            HelpDefinition(term: "Risk of Ruin", definition: "Kelly Criterion calculation with risk gauge. Shows if your position sizing is sustainable long-term.")
            HelpDefinition(term: "Behavioral Analytics (Discipline Score)", definition: "Detects 4 types of psychological mistakes: overtrading (2x average daily volume), revenge trading (re-entry within 10 minutes of loss), tilt events (3+ losses in 1 hour), and lot size escalation after losses. Gives A-F discipline grade.")
            HelpDefinition(term: "Consistency Score", definition: "5-dimension grading: win rate stability, profit factor consistency, drawdown recovery speed, sizing discipline, and timing consistency. Measures how repeatable your edge is.")
            HelpDefinition(term: "Sequence Analysis", definition: "Analyzes win/loss patterns. Detects momentum (streaks cluster), mean reversion (alternating), random (true edge), or tilt risk (consecutive losses likely).")

            HelpSubtitle("Position & Execution")
            HelpDefinition(term: "Position Sizer", definition: "Calculator: enter account size and risk %, get suggested lot size based on your average stop loss distance. Compares against actual sizing.")
            HelpDefinition(term: "Lot Size Analysis", definition: "Scatter plot of lot size vs P&L. Detects if larger positions lose more (overtrading signal).")
            HelpDefinition(term: "MAE/MFE Chart", definition: "Scatter plot: MAE (drawdown) vs MFE (best point). Top-right quadrant = efficient trades. Bottom-left = poor entries.")
            HelpDefinition(term: "Duration Analysis", definition: "P&L by trade duration bucket (0-5m, 5-15m, 15m-1h, 1-2h, 2h+). Finds your \"sweet spot\" hold time.")
            HelpDefinition(term: "Slippage Analysis", definition: "Distribution of slippage by bucket. Estimates total slippage cost and execution quality.")

            HelpSubtitle("Portfolio & Comparison")
            HelpDefinition(term: "Pair Analytics", definition: "Per-pair breakdown with mini equity curves and directional split. Shows which pairs carry your edge.")
            HelpDefinition(term: "Pair Correlation", definition: "Pearson correlation matrix between pairs. High positive correlation = concentrated risk. Negative correlation = good diversification.")
            HelpDefinition(term: "Benchmark Comparison", definition: "Compares your metrics against retail trader averages. Shows where you rank on win rate, PF, Sharpe, and drawdown.")
            HelpDefinition(term: "Prop Firm Tracker", definition: "Configurable tracker for prop firm challenge rules: profit target, daily loss limit, max drawdown. Shows progress toward each target.")

            HelpSubtitle("Grading & Quality")
            HelpDefinition(term: "Grade Distribution", definition: "Bar chart of A-F trade grades. Shows what percentage of trades meet high quality standards. Aim for 50%+ A/B grades.")
            HelpDefinition(term: "Trade Comparison", definition: "Side-by-side view of your best vs worst trade. Reverse-engineer what made the difference.")
            HelpDefinition(term: "Data Quality", definition: "Validation flags: missing R-multiples, oversized positions, zero-duration trades, duplicate close times, weekend trades. Ensures data integrity.")
            HelpDefinition(term: "Streak Timeline", definition: "Visual bar chart of win/loss streaks proportionally. Shows resilience to losing streaks.")

            HelpSubtitle("Sessions & Kill Zones")
            HelpDefinition(term: "Session Ranking", definition: "Ranks all sessions by P&L, win rate, and profit factor. Shows which sessions are worth your time and which to avoid.")
            HelpDefinition(term: "Kill Zone Optimizer", definition: "Analyzes your trade history to find the specific hour windows within each session where you have the strongest edge. Recommends optimal trading windows with supporting metrics. Exportable to CSV for EA integration.")
            HelpDefinition(term: "What to Cut Advisor", definition: "Identifies the sessions, hours, pairs, and conditions that are costing you money. Shows dollar impact of cutting each losing pattern. Exportable to CSV for EA integration.")

            HelpSubtitle("Behavioral & Emotional")
            HelpDefinition(term: "Emotional P&L Tracker", definition: "Tracks P&L by self-reported emotion (confident, anxious, frustrated, etc.). Reveals which emotional states produce better or worse trading outcomes.")
            HelpDefinition(term: "Checklist Compliance", definition: "Tracks how consistently you follow your pre-trade checklist. Compares P&L on checklist-compliant trades vs non-compliant trades.")
            HelpDefinition(term: "Commission & Fee Tracking", definition: "Tracks total commissions, swaps, and fees. Shows their impact on net profitability and cost per trade.")

            HelpSubtitle("Advanced Analysis")
            HelpDefinition(term: "Edge Decay Monitor", definition: "Tracks whether your edge is strengthening or weakening over time. Rolling profit factor and win rate windows reveal if your strategy is adapting or degrading.")
            HelpDefinition(term: "Time-to-MFE Analysis", definition: "Measures how long it takes for your trades to reach maximum favorable excursion. Helps optimize hold times and exit timing.")
            HelpDefinition(term: "Event Impact Profiler", definition: "Analyzes your P&L around major economic events (NFP, FOMC, CPI, ECB, BOE). Shows pre-event, during, and post-event performance with TRADE/CAUTION/AVOID recommendations per event type.")
            HelpDefinition(term: "Calendar Correlation", definition: "Maps your P&L against the economic calendar to find patterns — do you perform better or worse on news days?")
            HelpDefinition(term: "Net Currency Exposure", definition: "Shows your aggregate long/short exposure per currency across all open or historical trades. Reveals hidden concentration risk.")

            HelpSubtitle("Simulation & Projection")
            HelpDefinition(term: "Monte Carlo Simulation", definition: "1,000 randomized equity curve simulations. Shows percentile bands (5th to 95th), probability of profit, probability of hitting target, and probability of 20% drawdown. Answers: \"How likely is my system to work going forward?\"")
            HelpDefinition(term: "Improvement Tracker", definition: "Rolling metric trends over time. Shows if key metrics are improving, declining, or stable month-to-month.")

            HelpSubtitle("Sharing")
            HelpDefinition(term: "Shareable Summary", definition: "One-click copy of a formatted text summary for Discord or Telegram. Includes key metrics. Clipboard auto-clears after 30 seconds for security.")
        }
    }
}

// MARK: - AI Analysis

struct HelpAIAnalysis: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("AI-Powered Edge Detection")
            HelpParagraph("Dojix uses Claude AI to analyze your trade data and generate actionable recommendations.")

            HelpSubtitle("How It Works")
            HelpStep(number: 1, text: "Add your Anthropic API key in Settings (create one at console.anthropic.com).")
            HelpStep(number: 2, text: "Go to the Edge Report (Cmd+4) — requires 30+ trades.")
            HelpStep(number: 3, text: "Click \"Run Analysis\" to send your trade data to Claude for analysis.")
            HelpStep(number: 4, text: "Wait 10-30 seconds for AI-generated recommendations.")

            HelpSubtitle("What the AI Analyzes")
            HelpBullet("Session and hour performance patterns")
            HelpBullet("R-multiple distribution and position sizing")
            HelpBullet("Win rate and profit factor by pair, session, and day")
            HelpBullet("Duration patterns — are you holding too long or too short?")
            HelpBullet("Bias alignment effectiveness")
            HelpBullet("Volatility regime performance")
            HelpBullet("Post-close continuation (early exits)")

            HelpSubtitle("What You Get")
            HelpParagraph("3-5 ranked recommendations, each with:")
            HelpBullet("A specific, actionable suggestion (e.g., \"Focus on London session, avoid Late session\")")
            HelpBullet("Dollar impact estimate (e.g., \"Would have saved $340 over the analysis period\")")
            HelpBullet("Supporting data from your trade history")

            HelpSubtitle("API Key & Cost")
            HelpParagraph("You need your own Anthropic API key. AI analysis is optional and off until you add a key. Each analysis is one request billed to your own Anthropic account at Anthropic's current rates; Dojix never adds a charge. Only aggregated statistics are sent (no individual trades, tickets or notes), and only when you click Run Analysis. Your API key is stored securely in macOS Keychain — never sent anywhere except directly to Anthropic's API over HTTPS.")

            HelpWarning("AI recommendations are suggestions based on historical data. They are not financial advice. Always apply your own judgment and risk management.")
        }
    }
}
