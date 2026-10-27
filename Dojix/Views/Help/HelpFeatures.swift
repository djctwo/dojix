import SwiftUI

// MARK: - Journal

struct HelpJournal: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Trade Journal")
            HelpParagraph("The Journal is your complete trade log. Every imported trade appears here with full details, filtering, search, and export capabilities.")

            HelpSubtitle("Trade Table")
            HelpParagraph("The table shows 10 columns for each trade:")
            HelpBullet("Close Time — When the trade closed (click to open full detail sheet).")
            HelpBullet("Pair — Currency pair with color-coded icon.")
            HelpBullet("Direction — BUY or SELL badge.")
            HelpBullet("Lots — Position size.")
            HelpBullet("P&L — Net profit/loss, green for wins, red for losses.")
            HelpBullet("Cumulative P&L — Running total from earliest to current trade.")
            HelpBullet("R-Multiple — Risk-adjusted return (how many R you made/lost).")
            HelpBullet("Grade — A-F quality score based on execution, timing, and management.")
            HelpBullet("Session — Trading session badge (Asian, London, NY Overlap, etc.).")
            HelpBullet("Hour — UTC hour the trade was taken.")

            HelpSubtitle("Filters")
            HelpBullet("Pair: Filter by specific currency pair.")
            HelpBullet("Session: Filter by trading session (Asian, London, NY Overlap, New York, Late).")
            HelpBullet("Direction: Show only BUY or SELL trades.")
            HelpBullet("Date Range: Today, This Week, This Month, Last 30/90 Days, or All Time.")
            HelpBullet("Sort: Newest/Oldest first, Best/Worst P&L, Largest Win/Loss.")
            HelpBullet("Search: Search by symbol, ticket number, comment, notes, or tags.")

            HelpSubtitle("Performance Strip")
            HelpParagraph("Below the filters, a summary strip shows key metrics for your currently filtered trades: P&L, Win Rate, Profit Factor, Expectancy, Avg R, and Current Streak.")

            HelpSubtitle("Trade Detail Sheet")
            HelpParagraph("Click any trade to open a detail sheet showing all 32+ fields organized by section: Trade Info, Prices, Performance, Advanced metrics, Tags, Notes, and Metadata.")

            HelpSubtitle("Tags and Notes")
            HelpParagraph("Each trade can have user-defined tags (e.g., \"setup-A\", \"sniper\", \"revenge\") and free-text notes for trade reflections. Tags help you track which types of trades are profitable. Quick-suggest buttons offer common tags.")

            HelpTip("Use consistent tags like \"setup-A\" or \"news-trade\" to track which setups generate edge. View tag analytics in the Edge Report.")
        }
    }
}

// MARK: - Dashboard

struct HelpDashboard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Dashboard")
            HelpParagraph("The Dashboard is your analytics command center with 66 components organized across 6 tabs: Timing, Sessions, Pairs, Risk, Behavioral, and Advanced. All components react to the pair and date range filters in the toolbar.")

            HelpSubtitle("Toolbar Filters")
            HelpBullet("Pair Filter: Narrow all analytics to a specific currency pair, or view All Pairs.")
            HelpBullet("Date Range: All Time, This Week, This Month, Last 30 Days, Last 90 Days.")
            HelpBullet("Export: Save a PDF or CSV report of your dashboard data.")

            HelpSubtitle("Key Sections")
            HelpDefinition(term: "Quick Insight", definition: "A rotating data-driven insight bar at the top. It highlights your strongest pattern each day — best session, worst pair, win streak record, Sharpe warnings, or drawdown alerts.")
            HelpDefinition(term: "Metric Cards (12)", definition: "P&L, Win Rate, Profit Factor, Expectancy, Avg Win/Loss, Max Drawdown, Avg R-Multiple, Streaks, Avg Duration, Sharpe Ratio, Calmar Ratio. Each shows the primary metric with supporting context.")
            HelpDefinition(term: "Equity Curve", definition: "Your cumulative P&L plotted over time. An upward-trending curve indicates consistent edge.")
            HelpDefinition(term: "Drawdown Chart", definition: "Shows how far below peak equity you are at any point. Deeper drawdowns mean higher risk periods.")
            HelpDefinition(term: "Trade Calendar", definition: "Color-coded grid showing P&L per day. Green = profitable day, Red = losing day. Spot patterns at a glance.")

            HelpParagraph("See the Analytics Components help topic for detailed explanations of all 66 components.")

            HelpTip("Use the pair filter to isolate analytics for a specific currency pair. This reveals pair-specific edge that might be hidden in portfolio-level data.")
        }
    }
}

// MARK: - Edge Report

struct HelpEdgeReport: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Edge Report")
            HelpParagraph("The Edge Report answers the most important question in trading: where exactly do you make and lose money? It requires at least 30 trades to generate meaningful analysis.")

            HelpSubtitle("Edge Breakdowns")
            HelpParagraph("Four cards show your top 5 money-makers and top 5 money-losers across four dimensions:")
            HelpBullet("By Session: Which sessions (Asian, London, NY, etc.) are most/least profitable.")
            HelpBullet("By Hour: Which UTC hours produce the best/worst results.")
            HelpBullet("By Pair: Which currency pairs make/lose the most money.")
            HelpBullet("By Day: Which weekdays are strongest/weakest.")
            HelpParagraph("Each entry shows P&L in dollars, trade count, and win rate. Dollar values make the impact concrete — \"London session: +$2,340 over 45 trades\" is actionable.")

            HelpSubtitle("Bias Alignment")
            HelpParagraph("Shows your P&L broken down by whether trades aligned WITH, AGAINST, or were NEUTRAL to the higher-timeframe bias. Helps you decide whether to filter for bias alignment.")

            HelpSubtitle("Volatility Regime")
            HelpParagraph("Shows P&L by volatility conditions (Low, Medium, High). Reveals whether you trade better in calm or volatile markets.")

            HelpSubtitle("Post-Close Analysis")
            HelpParagraph("Measures how far price continued in your trade's direction after you exited. If price consistently moves 20+ pips after your exit, you may be closing too early.")

            HelpSubtitle("AI Analysis")
            HelpParagraph("Click \"Run Analysis\" to get AI-powered recommendations.")
            HelpParagraph("Claude AI analyzes your complete trade data and returns 3-5 ranked recommendations with specific dollar impact estimates. See the AI Analysis help topic for details.")
        }
    }
}

// MARK: - Pulse

struct HelpPulse: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Pulse — Live Session Intelligence")
            HelpParagraph("Pulse gives you real-time context for your trading: what session is active, what news events are coming, and whether conditions match your historical edge.")

            HelpSubtitle("Session Clock")
            HelpParagraph("Shows the current active forex session with a colored indicator, your local time, UTC time, and time remaining in the session. During session overlaps (e.g., London + NY), Pulse displays all active sessions simultaneously with a \"2 Sessions Active\" header and color dots for each. Also visible in the sidebar widget, updating every second.")

            HelpSubtitle("Edge Signal")
            HelpParagraph("A personalized signal based on your trade history and current conditions:")
            HelpBullet("Strong (green): Your historical win rate and profit factor are high in the current session and hour. Conditions match your edge — stay focused.")
            HelpBullet("Neutral (orange): Mixed signals or insufficient data. Trade with caution.")
            HelpBullet("Avoid (red): Poor historical performance in current conditions, or a high-impact news event is active. Consider sitting out.")
            HelpParagraph("Requires 30+ trades to generate personalized signals.")

            HelpSubtitle("Per-Session Edge Signals")
            HelpParagraph("During session overlaps, each active session gets its own expandable card with independent edge signal, trade count, win rate, profit factor, and P&L from your history.")
            HelpParagraph("Compare your edge across overlapping sessions (e.g., London vs NY Overlap performance) in real time.")

            HelpSubtitle("Economic Calendar")
            HelpParagraph("Full-week economic calendar grouped by day with high-impact event counts.")
            HelpBullet("High impact (red): Major events like NFP, GDP, CPI — can cause large moves.")
            HelpBullet("Medium impact (orange): Moderate market-moving potential.")
            HelpBullet("Low impact (gray): Minor events, usually safe to trade through.")
            HelpParagraph("Today is highlighted with a gold badge. High-impact events show your historical performance inline (e.g., \"Your history: 3W/2L, +$12.50 avg\"). Danger Zone alerts warn you 15 minutes before and after high-impact events, showing which pairs to avoid.")

            HelpSubtitle("Live Prices")
            HelpParagraph("Real-time forex quotes for your watchlist pairs.")
            HelpParagraph("Shows price, daily change, and change percentage. Click the settings icon to customize your watchlist (up to 8 pairs from 23 available). Dojix supports 5 live data sources — select your preferred source in Settings:")
            HelpBullet("Twelve Data REST (default): Polls every 2 minutes, free tier with 800 requests/day.")
            HelpBullet("Twelve Data WebSocket: Real-time streaming, requires paid Twelve Data plan.")
            HelpBullet("OANDA Streaming: Real-time via v20 API, free with an OANDA account.")
            HelpBullet("Polygon.io WebSocket: Real-time streaming, requires Polygon.io subscription.")
            HelpBullet("MT5 Direct: Reads price feed files from your local MT5 installation.")

            HelpSubtitle("Currency Strength")
            HelpParagraph("Horizontal bars showing relative strength of major currencies based on current price movements. Positive = strengthening, Negative = weakening.")
        }
    }
}

// MARK: - Trade Replay

struct HelpTradeReplay: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Trade Replay")
            HelpParagraph("Trade Replay lets you step through your trades chronologically, watching your equity curve build trade by trade. It's a powerful learning tool for reviewing what happened and when.")

            HelpSubtitle("How to Use")
            HelpStep(number: 1, text: "Go to the Journal tab (Cmd+1).")
            HelpStep(number: 2, text: "Click the \"Replay\" button in the toolbar (requires 2+ trades).")
            HelpStep(number: 3, text: "Use the controls to step through trades or play automatically.")

            HelpSubtitle("Controls")
            HelpBullet("Play/Pause: Automatically advance through trades at the selected speed.")
            HelpBullet("Step Forward/Back: Move one trade at a time.")
            HelpBullet("Rewind: Jump back to the first trade.")
            HelpBullet("Skip to End: Jump to the last trade.")
            HelpBullet("Speed: Adjust playback speed (0.5x, 1x, 2x, 5x).")

            HelpSubtitle("What You See")
            HelpBullet("Equity Curve: Builds in real-time as you step through trades, with a marker on the current position.")
            HelpBullet("Running Stats: Live-updating P&L, win/loss count, win rate, and current streak.")
            HelpBullet("Trade Card: Full details of the current trade — pair, direction, session, time, R-multiple, MAE, MFE, and running context (progress through total trades, average P&L, peak equity, current drawdown).")

            HelpTip("Use replay to study your losing streaks. Step through slowly and look for patterns — were you overtrading? Trading the wrong session? Ignoring bias alignment?")
        }
    }
}
