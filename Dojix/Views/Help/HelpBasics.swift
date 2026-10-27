import SwiftUI

// MARK: - Getting Started

struct HelpGettingStarted: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Getting Started with Dojix")
            HelpParagraph("Dojix is a native Mac app for forex trade journaling, AI-powered edge detection, and live session intelligence. It analyzes your trading history to find where you make money, where you lose it, and what to do about it.")

            HelpSubtitle("First Launch")
            HelpParagraph("When you first open Dojix, the onboarding wizard walks you through setup in 8 steps:")
            HelpStep(number: 1, text: "Welcome — Overview of what Dojix does.")
            HelpStep(number: 2, text: "Import — How to import trades from CSV files or connect to MT5.")
            HelpStep(number: 3, text: "Journal — Tour of the trade log, filters, search, and trade detail sheets.")
            HelpStep(number: 4, text: "Dashboard — Overview of the 66 analytics components across 6 tabs.")
            HelpStep(number: 5, text: "Edge Report — How the AI-powered edge detection works.")
            HelpStep(number: 6, text: "Pulse — Live session intelligence, economic calendar, and live prices.")
            HelpStep(number: 7, text: "Quick Setup — Configure MT5 path and API keys (optional — you can set these later in Settings).")
            HelpStep(number: 8, text: "Ready — Quick start guide. You can load 30 sample trades to explore the app immediately.")

            HelpTip("If you don't use MT5, skip step 2. You can import trades from any platform using CSV files.")

            HelpSubtitle("Your First Analysis")
            HelpParagraph("After importing trades, here's the recommended workflow:")
            HelpStep(number: 1, text: "Go to the Journal (Cmd+1) to review your imported trades. Use filters to explore by pair, session, or date range.")
            HelpStep(number: 2, text: "Go to the Dashboard (Cmd+2) to see your portfolio overview — equity curve, win rate, profit factor, and key metrics.")
            HelpStep(number: 3, text: "Open Analytics (Cmd+3) for deep-dive analysis — 60+ components across Timing, Sessions, Pairs, Risk, Behavioral, and Advanced tabs.")
            HelpStep(number: 4, text: "Go to the Edge Report (Cmd+4) once you have 30+ trades. This shows your top money-makers and money-losers by session, hour, pair, and day.")
            HelpStep(number: 5, text: "Check Pulse (Cmd+5) for live session intelligence — current session, economic calendar, live quotes, and your personalized edge signal.")

            HelpSubtitle("Daily Routine")
            HelpBullet("Morning: Check Pulse for today's economic calendar and session schedule.")
            HelpBullet("After trading: Import your latest trades and review in the Journal. Add notes and tags.")
            HelpBullet("Weekly: Review the Edge Report and Dashboard for patterns. Run AI analysis for recommendations.")
            HelpBullet("Monthly: Check Monthly Returns, Growth Projection, and Consistency Score for long-term trends.")
        }
    }
}

// MARK: - Importing Trades

struct HelpImportingTrades: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Importing Trades")
            HelpParagraph("Dojix supports importing trades from CSV files. You can import from any trading platform that exports trade history as CSV.")

            HelpSubtitle("Import Methods")

            HelpDefinition(term: "Drag and Drop", definition: "Drag a CSV file directly onto the Import tab's drop zone. The file will be parsed and imported automatically.")
            HelpDefinition(term: "File Picker", definition: "Click \"Choose File\" on the Import tab to open a file browser and select your CSV file.")
            HelpDefinition(term: "MT5 Auto-Scan", definition: "Click \"Scan MT5 Folder\" to automatically find and import StrategyAnalytics CSV files from your configured MT5 directory. Requires MT5 path to be set in Settings.")

            HelpSubtitle("Duplicate Handling")
            HelpParagraph("Dojix uses the ticket number as a unique identifier. If you import the same file twice, duplicate trades are automatically skipped. This means you can safely re-import without creating duplicate entries.")

            HelpSubtitle("After Import")
            HelpParagraph("After a successful import, Dojix automatically navigates to the Dashboard so you can see your updated analytics. A success toast confirms how many trades were imported.")

            HelpSubtitle("Supported Platforms")
            HelpParagraph("See the Platform Import Guides section in the sidebar for step-by-step instructions for your specific trading platform: MT5, MT4, cTrader, TradingView, OANDA, Interactive Brokers, Thinkorswim, and NinjaTrader.")

            HelpTip("Import at least 30 trades to unlock the Edge Report and get meaningful analytics. The more history you import, the more reliable the pattern detection becomes.")

            HelpSubtitle("Import Errors")
            HelpParagraph("If an import fails, Dojix shows an error message explaining what went wrong:")
            HelpBullet("\"Expected 32 columns\" — The CSV format doesn't match. Check that you're using the correct export from your platform.")
            HelpBullet("\"Unsupported encoding\" — The file uses an uncommon character encoding. Try re-exporting as UTF-8.")
            HelpBullet("\"No trade detail section found\" — The CSV doesn't contain the expected trade data section.")
        }
    }
}

// MARK: - Exporting Data

struct HelpExportingData: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Exporting Data")
            HelpParagraph("Dojix supports exporting your trade data and analytics reports in multiple formats.")

            HelpSubtitle("CSV Export")
            HelpParagraph("Export your full trade data as a CSV file.")
            HelpBullet("Available from the Journal and Dashboard toolbar export menu.")
            HelpBullet("Includes 27 columns covering all trade details, metrics, and tags.")
            HelpBullet("Formula injection prevention: fields starting with =, +, @, or - are safely escaped.")
            HelpBullet("UTF-8 encoded, compatible with Excel, Google Sheets, and Numbers.")

            HelpSubtitle("PDF Export")
            HelpParagraph("Export formatted reports as multi-page PDF documents.")
            HelpBullet("Journal Report: Trade list table with summary metrics (P&L, win rate, profit factor, expectancy, streaks, drawdown).")
            HelpBullet("Dashboard Report: Key metrics, grade distribution, performance tables by session/pair/day/hour, monthly P&L, risk assessment.")
            HelpBullet("Edge Report: AI recommendations, edge breakdowns, bias and volatility analysis.")

            HelpSubtitle("Data Backup")
            HelpParagraph("Export a full backup of your Dojix database from Settings > Data > Export Backup. The backup file (.dojix) contains all your trades, notes, tags, checkpoints and settings; screenshots are not included. You can restore from a backup at any time.")
            HelpParagraph("Protect this backup with a password (recommended): the file is encrypted with AES-256-GCM using a key derived from that password (PBKDF2-SHA256, 600,000 iterations, random salt), so it can't be read or changed without the password. The option is on by default when App Lock is on. The password needs at least 8 characters, and there is no way to recover a forgotten one.")
            HelpParagraph("Without a password, a backup is an unencrypted copy of your journal database. Anyone who gets the file can read your trades, so store it somewhere private. Either way the file is saved readable only by your macOS user account.")
            HelpParagraph("Restore Backup asks for the password if the backup has one (password-protected backups from older Dojix versions restore too). Restoring checks the file first (the password, that it is a Dojix backup made by this or an older version, with every value in range) and refuses it otherwise; your journal is then left unchanged. A restore replaces the trades in your journal, so export a backup of your current journal first if you may want it back.")
        }
    }
}
