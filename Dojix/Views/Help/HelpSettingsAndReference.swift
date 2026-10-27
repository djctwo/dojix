import SwiftUI

// MARK: - Settings

struct HelpSettings: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Settings")
            HelpParagraph("Access Settings via Cmd+, or the Settings tab in the sidebar.")

            HelpSubtitle("AI Analysis")
            HelpParagraph("Optional. Enter your own Anthropic API key to turn on AI recommendations in the Edge Report (usage is billed to your Anthropic account). The key is stored securely in macOS Keychain and only sent to Anthropic's API over HTTPS. Get a key at console.anthropic.com.")

            HelpSubtitle("Live Market Data")
            HelpParagraph("Select your preferred live data source and enter the required API key. Dojix supports 5 data sources:")
            HelpBullet("Twelve Data REST (default): Polls every 2 minutes. Free tier at twelvedata.com gives 800 requests/day.")
            HelpBullet("Twelve Data WebSocket: Real-time streaming. Requires a paid Twelve Data plan.")
            HelpBullet("OANDA Streaming: Real-time via v20 API. Free with any OANDA account.")
            HelpBullet("Polygon.io WebSocket: Real-time streaming. Requires a Polygon.io subscription.")
            HelpBullet("MT5 Direct: Reads price feed files from your local MT5 installation. No API key needed.")

            HelpSubtitle("MT5 Integration")
            HelpParagraph("Set the path to your MT5 Common Files folder for auto-scanning SA CSV files. Click Browse to navigate to the correct directory. A green checkmark confirms the path is valid.")

            HelpSubtitle("Data Management")
            HelpBullet("Trade Count: Shows how many trades are in your database.")
            HelpBullet("Export Backup: Save a full copy of your database for safekeeping, optionally protected with a password (recommended; see Data Backup).")
            HelpBullet("Restore Backup: Load a previously exported backup (it asks for the password if the backup has one). The file is checked before anything changes; a restore replaces the trades in your journal.")
            HelpBullet("Delete All Trades: Permanently removes all trade data. Requires confirmation. Cannot be undone.")

            HelpSubtitle("Security")
            HelpParagraph("Enable or disable App Lock (your journal's key is protected by your password), change its password, and choose \"Lock when idle\". See the App Lock help topic for details.")

            HelpSubtitle("About")
            HelpParagraph("Shows app version, build number, and database info. Bugs and ideas can be reported as issues on the project's GitHub page.")
        }
    }
}

// MARK: - App Lock

struct HelpAppLock: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("App Lock")
            HelpParagraph("App Lock protects your journal with a password. When it is on, the key that decrypts your journal is itself encrypted with your password, so nothing can be read, by Dojix or by anyone copying its files, until the password is entered.")

            HelpSubtitle("Enabling App Lock")
            HelpStep(number: 1, text: "Go to Settings > Security.")
            HelpStep(number: 2, text: "Click \"Enable App Lock\".")
            HelpStep(number: 3, text: "Enter a password (minimum 8 characters) and confirm it.")
            HelpStep(number: 4, text: "App Lock is now active. You'll see the lock screen the next time you open Dojix, and whenever Dojix locks itself: after the \"Lock when idle\" time with no keyboard or mouse activity in Dojix, when you hide it or minimize its window, when your screen locks or goes to sleep, when your Mac sleeps, and when you switch to another user account. If one of these happens while Dojix is still checking your password, it locks as soon as the check finishes.")

            HelpSubtitle("Lock When Idle")
            HelpParagraph("Settings > Security > Lock when idle: Off, or after 1, 5, 15, 30 or 60 minutes without keyboard or mouse activity in Dojix (default 15 minutes). Activity in other apps doesn't count. Locking closes any open sheet or file dialog, so only the lock screen stays visible.")

            HelpSubtitle("Security Details")
            HelpBullet("Your journal is encrypted with AES-256-GCM. While Dojix runs, the decrypted journal exists only in memory; on disk there is only the encrypted file, saved (and flushed to the disk) after every change.")
            HelpBullet("With App Lock on, the journal's key is wrapped with a key derived from your password (PBKDF2-SHA256, 600,000 iterations, random salt). Your password itself is never stored.")
            HelpBullet("With App Lock off, the journal is still encrypted on disk, and its key is kept in your Mac's Keychain.")
            HelpBullet("When Dojix locks itself, it saves your journal and clears the decrypted copy and its key from memory.")
            HelpBullet("Older-copy check: every save is numbered, and the number is stored inside the encrypted journal and in your Mac's Keychain. If the journal file is ever replaced with an older copy (or one from a line of changes you abandoned), Dojix doesn't open it silently: it says \"This journal is older than the last one this Mac saved\" and opens it only after you enter your App Lock password (with App Lock off: after you confirm). This works as long as macOS lets Dojix update its Keychain record: if macOS asks about Dojix's Keychain items (for example after an update), choose Always Allow. If the record can't be read or updated, Dojix keeps working, and a copy at least as new as the last number it could store opens without the warning. Restoring a backup from Settings never triggers this.")
            HelpBullet("After 5 wrong passwords, Dojix makes you wait before trying again. This counts every place that asks for the password: the lock screen and Settings.")
            HelpBullet("Changing the password or turning App Lock off needs your current password.")
            HelpBullet("Turning App Lock on or changing its password gives your journal and screenshots a new key. The new password works as soon as Dojix says the change was made. If a file can't be re-encrypted right away (for example, a screenshot that can't be written), Dojix says it will finish the next time you unlock, and keeps the old key until the journal and every copy and screenshot it finds open with the new one (a folder it can't read counts as not done yet), so nothing becomes unreadable.")
            HelpBullet("On one Mac, only one copy of Dojix can use your journal at a time: if another copy is already running, the second one says \"Dojix is already open\" and opens nothing. This needs a data folder that supports file locks (a normal folder on your Mac does). In a folder where the lock can't be taken, such as some network folders, Dojix opens anyway, and it can't see a copy running on another Mac.")

            HelpSubtitle("Forgot Your Password?")
            HelpParagraph("There is no password recovery: without the password the journal can't be decrypted. Click \"Forgot Password?\" on the lock screen to erase all local data (trades, notes, screenshots and saved API keys) and start fresh. If Dojix is still checking a password or changing its key, the erase waits for that to finish first. Exported backups are not affected, so you can restore one afterwards.")

            HelpWarning("Backups exported without a password are not encrypted: anyone who gets the file can read it, so use \"Protect this backup with a password\". For full-disk protection, also enable FileVault on your Mac (System Settings > Privacy & Security > FileVault).")
        }
    }
}

// MARK: - Keyboard Shortcuts

struct HelpKeyboardShortcuts: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Keyboard Shortcuts")
            HelpParagraph("Navigate Dojix quickly using these keyboard shortcuts.")

            HelpSubtitle("Navigation")
            shortcutRow("Journal", "Cmd + 1")
            shortcutRow("Dashboard", "Cmd + 2")
            shortcutRow("Analytics", "Cmd + 3")
            shortcutRow("Edge Report", "Cmd + 4")
            shortcutRow("Pulse", "Cmd + 5")
            shortcutRow("Import", "Cmd + 6")
            shortcutRow("Settings", "Cmd + ,")

            HelpSubtitle("General")
            shortcutRow("Confirm / Submit", "Return")
            shortcutRow("Cancel / Dismiss", "Escape")
            shortcutRow("Unlock App", "Return")
        }
    }

    private func shortcutRow(_ action: String, _ shortcut: String) -> some View {
        HStack {
            Text(action)
                .font(.body)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(shortcut)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.borderCard, lineWidth: 1)
        )
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Glossary

struct HelpGlossary: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Glossary")
            HelpParagraph("Key trading and analytics terms used in Dojix.")

            HelpSubtitle("Trading Terms")
            HelpDefinition(term: "Lot", definition: "A unit of trade size. 1 standard lot = 100,000 units of the base currency. 0.1 = mini lot (10,000). 0.01 = micro lot (1,000).")
            HelpDefinition(term: "Pip", definition: "The smallest standard price movement. For most pairs, 1 pip = 0.0001. For JPY pairs, 1 pip = 0.01.")
            HelpDefinition(term: "Spread", definition: "The difference between bid and ask price. Your cost of entering a trade.")
            HelpDefinition(term: "Slippage", definition: "The difference between your expected fill price and actual fill price. Higher during news events or low liquidity.")
            HelpDefinition(term: "Swap", definition: "The overnight interest charge or credit for holding a position past the daily rollover time.")
            HelpDefinition(term: "Stop Loss (SL)", definition: "A pre-set price level where your trade automatically closes to limit losses.")
            HelpDefinition(term: "Take Profit (TP)", definition: "A pre-set price level where your trade automatically closes to lock in profits.")

            HelpSubtitle("Session Terms")
            HelpDefinition(term: "Asian Session", definition: "00:00-09:00 UTC. Covers Tokyo, Sydney, and Singapore markets. Generally lower volatility.")
            HelpDefinition(term: "London Session", definition: "07:00-16:00 UTC. The highest-volume forex session. Overlaps with both Asian and New York.")
            HelpDefinition(term: "NY Overlap", definition: "12:00-16:00 UTC. When London and New York sessions overlap. Highest volatility and volume period.")
            HelpDefinition(term: "New York Session", definition: "12:00-21:00 UTC. Second-highest volume session after London.")
            HelpDefinition(term: "Late Session", definition: "21:00-00:00 UTC. Low liquidity period between NY close and Asian open. Generally avoid trading.")
            HelpDefinition(term: "Kill Zone", definition: "ICT concept — specific high-probability time windows within sessions where institutional order flow concentrates.")

            HelpSubtitle("Analytics Terms")
            HelpDefinition(term: "MAE (Maximum Adverse Excursion)", definition: "The worst drawdown during a trade. How far price moved against you before the trade closed.")
            HelpDefinition(term: "MFE (Maximum Favorable Excursion)", definition: "The best unrealized profit during a trade. How far price moved in your favor before the trade closed.")
            HelpDefinition(term: "R-Multiple", definition: "Profit/loss as a multiple of initial risk. 2R = you made 2x your risk. -0.5R = you lost half your risk.")
            HelpDefinition(term: "Profit Factor", definition: "Gross profit / gross loss. Above 1.0 = profitable. Above 2.0 = excellent.")
            HelpDefinition(term: "Expectancy", definition: "Average expected profit per trade. (Win% x Avg Win) - (Loss% x Avg Loss).")
            HelpDefinition(term: "Sharpe Ratio", definition: "Risk-adjusted return metric. Average return / standard deviation of returns. Higher = better.")
            HelpDefinition(term: "Calmar Ratio", definition: "Annualized return / max drawdown. Measures return per unit of drawdown risk.")
            HelpDefinition(term: "Kelly Criterion", definition: "Optimal bet sizing formula based on win rate and reward-to-risk ratio.")

            HelpSubtitle("ICT / Smart Money Terms")
            HelpDefinition(term: "Sweep / Liquidity Grab", definition: "Price briefly exceeds a key level (support, resistance, or previous high/low) to trigger stop losses, then reverses. Used by institutional traders to fill large orders.")
            HelpDefinition(term: "FVG (Fair Value Gap)", definition: "A price imbalance visible on charts where price moved so quickly it left a gap. Often acts as a magnet — price returns to fill the gap.")
            HelpDefinition(term: "Bias", definition: "The expected directional move based on higher-timeframe analysis. Trading \"with bias\" means trading in the direction of the higher-timeframe trend.")
            HelpDefinition(term: "Bias Alignment", definition: "Whether your trade direction matched (WITH), opposed (AGAINST), or was unrelated to (NEUTRAL) the higher-timeframe bias.")
            HelpDefinition(term: "Volatility Regime", definition: "Market conditions categorized as LOW, MED, or HIGH based on Average True Range or daily range size.")
        }
    }
}

// MARK: - FAQ

struct HelpFAQ: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Frequently Asked Questions")

            faqItem(
                question: "How many trades do I need for meaningful analytics?",
                answer: "The Edge Report requires 30 trades minimum. For statistically significant patterns, 100+ trades is ideal. Monte Carlo simulation and consistency scoring become more reliable with larger samples. Import as much history as you have."
            )
            faqItem(
                question: "Can I import from multiple platforms?",
                answer: "Yes. Dojix uses ticket numbers as unique identifiers. You can import from different platforms and all trades appear in the same journal and analytics. Just make sure ticket numbers don't collide across platforms."
            )
            faqItem(
                question: "Is my data sent anywhere?",
                answer: "Only if you choose to use AI Analysis with your own Anthropic API key. When you click \"Run Analysis\" in the Edge Report, your aggregated trade statistics (not individual trades) are sent to Anthropic's Claude API for analysis. Your API keys are stored locally in macOS Keychain. No data is sent to Dojix servers — there are no Dojix servers."
            )
            faqItem(
                question: "Where is my data stored?",
                answer: "All trade data is stored locally on your Mac at ~/Library/Application Support/Dojix/. The journal file (Dojix.sqlite) and your screenshots are always encrypted on disk; the decrypted journal exists only in Dojix's memory while it runs. The encryption key is in macOS Keychain (wrapped with your App Lock password if App Lock is on), as are your API keys. Nothing is stored in the cloud."
            )
            faqItem(
                question: "Can I use Dojix offline?",
                answer: "Yes. All analytics, journaling, and export features work offline. Only live quotes (Pulse), economic calendar, and AI analysis require an internet connection."
            )
            faqItem(
                question: "What happens if I delete Dojix?",
                answer: "Your trade database persists at ~/Library/Application Support/Dojix/ even after deleting the app. Reinstalling Dojix will pick up your existing data. To fully remove data, delete this folder manually."
            )
            faqItem(
                question: "How is the trade grade calculated?",
                answer: "Each trade is scored on 4 dimensions (25 points each): R-Multiple quality (higher R = better), Execution efficiency (MFE-to-MAE ratio), Timing discipline (session quality, prime hours, bias alignment), and Trade management (breakeven usage, duration, post-close capture). Grades: A (80+), B (65+), C (50+), D (35+), F (<35)."
            )
            faqItem(
                question: "What does the Edge Signal in Pulse mean?",
                answer: "The edge signal combines your historical performance in the current session and hour with live market conditions. \"Strong\" means conditions match where you historically make money. \"Avoid\" means conditions match where you historically lose money or a high-impact news event is active."
            )
            faqItem(
                question: "Can I use Dojix for stocks or crypto?",
                answer: "Dojix is designed specifically for forex trading — sessions, pip calculations, and pair analysis are forex-specific. You can import non-forex trades, but some analytics (session detection, currency strength) won't apply."
            )
        }
    }

    private func faqItem(question: String, answer: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(question)
                .font(.body)
                .fontWeight(.semibold)
            Text(answer)
                .font(.callout)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Troubleshooting

struct HelpTroubleshooting: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Troubleshooting")

            HelpSubtitle("Import Fails with \"Expected 32 columns\"")
            HelpParagraph("This means the CSV file doesn't match the StrategyAnalytics format. If you're importing from a different platform, the column layout is different. Check the Platform Import Guides section for your specific platform's export format.")

            HelpSubtitle("Import Fails with \"Unsupported encoding\"")
            HelpParagraph("The CSV file uses a character encoding Dojix can't read. Open the file in a text editor (TextEdit, VS Code) and re-save it as UTF-8 encoding.")

            HelpSubtitle("No Trades Appear After Import")
            HelpBullet("Check the Journal filters — you may have a pair, session, or date range filter active that hides the imported trades.")
            HelpBullet("Click \"All Pairs\", \"All Sessions\", and \"All Time\" to reset filters.")
            HelpBullet("The import may have been all duplicates if you imported the same file twice.")

            HelpSubtitle("Live Quotes Not Loading")
            HelpBullet("Check which data source is selected in Settings > Live Market Data.")
            HelpBullet("Twelve Data REST: Verify API key, check if you've exceeded the daily limit (800 requests on free tier).")
            HelpBullet("Twelve Data WebSocket: Requires a paid Twelve Data plan for streaming access.")
            HelpBullet("OANDA Streaming: Verify your OANDA API key and account type (practice or live).")
            HelpBullet("Polygon.io WebSocket: Verify your Polygon.io API key and subscription level.")
            HelpBullet("MT5 Direct: Verify your MT5 Common Files path is correct and MT5 is running with the price feed EA active.")
            HelpBullet("Ensure you have an internet connection (except MT5 Direct which reads local files).")
            HelpBullet("Quotes are only available on weekdays when forex markets are open.")

            HelpSubtitle("AI Analysis Fails")
            HelpBullet("Verify your Anthropic API key is entered correctly in Settings > AI Analysis.")
            HelpBullet("Ensure you have at least 30 trades imported.")
            HelpBullet("Check your internet connection.")
            HelpBullet("If you see a rate limit error, wait a few minutes and try again.")

            HelpSubtitle("App Feels Slow with Many Trades")
            HelpParagraph("Dojix is optimized for 10,000+ trades. If performance degrades, try narrowing the date range filter on the Dashboard. The LazyVStack rendering loads components as you scroll.")

            HelpSubtitle("Database Reset Warning")
            HelpParagraph("If Dojix says your journal database could not be opened and it started a new, empty one, the file was damaged or could not be decrypted with your key (rare). The old file is kept (renamed, never deleted) in Dojix's data folder. If you had a backup, restore it from Settings > Data > Restore Backup.")
            HelpParagraph("If Dojix says it couldn't read your journal file, the file was left exactly as it was and nothing was opened (for example, the disk is failing or the file's permissions changed). Fix that, then quit and reopen Dojix. If the disk is full, Dojix still opens your journal but tells you it couldn't save it: free up space so your changes are saved.")

            HelpSubtitle("Can't Find MT5 Common Files Folder")
            HelpParagraph("On Mac, MT5 runs through Wine. The Common Files folder is typically at:")
            HelpParagraph("~/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5/Files/")
            HelpParagraph("Note: The Library folder is hidden by default. In Finder, press Cmd+Shift+. to show hidden files, or use the Browse button in Settings which can navigate to hidden folders.")

            HelpSubtitle("Need More Help?")
            HelpParagraph("Click \"Send Feedback\" in Settings > About to email us with your issue. Please include your Dojix version and a description of the problem.")
        }
    }
}
