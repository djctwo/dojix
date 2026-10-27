import SwiftUI

// MARK: - MT5

struct HelpImportMT5: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Import from MetaTrader 5")
            HelpParagraph("Dojix has native MT5 support via StrategyAnalytics CSV files. This is the richest import format, providing all 32 metrics including MAE, MFE, R-multiples, session tagging, bias alignment, and post-close continuation.")

            HelpSubtitle("Option A: StrategyAnalytics CSV")
            HelpParagraph("If you have an MT5 analytics script that writes the 32-column StrategyAnalytics CSV format (file names starting with StrategyAnalytics_Results_):")
            HelpStep(number: 1, text: "In MT5, run the script on any chart. It scans your trade history and generates a CSV file.")
            HelpStep(number: 2, text: "The CSV is saved to your MT5 Common Files folder (typically ~/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5/Files/).")
            HelpStep(number: 3, text: "In Dojix, go to Import (Cmd+6) and drag the CSV file onto the drop zone, or click \"Choose File\".")
            HelpStep(number: 4, text: "Dojix parses all 32 columns and imports your trades with full analytics data.")

            HelpWarning("Times in StrategyAnalytics files are your broker server's clock, and Dojix currently reads them as UTC. Many MT5 brokers run on UTC+2 or UTC+3, so hour and session statistics from these files can be shifted by that many hours. Platform CSVs with real UTC times (and OANDA imports) are not affected.")
            HelpTip("Click \"Scan MT5 Folder\" to auto-detect and import all SA CSV files. Set your MT5 path in Settings first.")

            HelpSubtitle("Option B: MT5 Built-in History Export")
            HelpParagraph("If you don't use StrategyAnalytics, you can export from MT5 directly:")
            HelpStep(number: 1, text: "In MT5, go to the Toolbox panel (Ctrl+T) and click the \"History\" tab.")
            HelpStep(number: 2, text: "Right-click anywhere in the history list and select a time period (or \"All History\").")
            HelpStep(number: 3, text: "Right-click again and choose \"Report\" > \"Open XML\" or copy to clipboard.")
            HelpStep(number: 4, text: "Save the data as a CSV file and import into Dojix.")

            HelpWarning("The built-in MT5 export has fewer fields than StrategyAnalytics. Advanced metrics like MAE, MFE, R-multiples, and session tagging will be calculated from available data or set to defaults.")

            HelpSubtitle("MT5 on Mac")
            HelpParagraph("MT5 runs on Mac through a Wine wrapper. The Common Files path is typically at: ~/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5/Files/")
            HelpParagraph("You can set this path in Settings > MT5 Integration. Use the Browse button to navigate to the correct folder.")
        }
    }
}

// MARK: - MT4

struct HelpImportMT4: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Import from MetaTrader 4")
            HelpParagraph("MT4 is the most widely used forex platform globally. You can export your trade history as a detailed statement.")

            HelpSubtitle("How to Export from MT4")
            HelpStep(number: 1, text: "Open MT4 and go to the Terminal panel (Ctrl+T).")
            HelpStep(number: 2, text: "Click the \"Account History\" tab.")
            HelpStep(number: 3, text: "Right-click in the history area and select the time period you want (\"All History\" for complete data).")
            HelpStep(number: 4, text: "Right-click again and select \"Save as Report\" or \"Save as Detailed Report\".")
            HelpStep(number: 5, text: "MT4 saves an HTML file (.htm). Open this file in a spreadsheet app (Excel, Google Sheets, Numbers).")
            HelpStep(number: 6, text: "Select the trade rows (skip headers and summary) and save as CSV.")
            HelpStep(number: 7, text: "Import the CSV into Dojix.")

            HelpTip("Choose \"Detailed Report\" for the most complete data. It includes swap, commission, and additional trade details that improve Dojix analytics accuracy.")

            HelpSubtitle("Expected Columns")
            HelpParagraph("MT4 detailed reports typically include: Ticket, Open Time, Type (buy/sell), Size (lots), Item (symbol), Price (open), S/L, T/P, Close Time, Price (close), Commission, Swap, Profit.")

            HelpSubtitle("MT4 on Mac")
            HelpParagraph("MT4 also runs via Wine/CrossOver on Mac. The history files are saved in the MT4 data folder, typically at: ~/Library/Application Support/net.metaquotes.wine.metatrader4/ or similar path depending on your broker's MT4 installation.")
        }
    }
}

// MARK: - cTrader

struct HelpImportCTrader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Import from cTrader")
            HelpParagraph("cTrader is popular with prop firms and serious retail traders. It has excellent trade history export capabilities.")

            HelpSubtitle("How to Export from cTrader Desktop")
            HelpStep(number: 1, text: "Open cTrader and go to the History tab at the bottom of the platform.")
            HelpStep(number: 2, text: "Set your date range using the calendar controls (start date and end date).")
            HelpStep(number: 3, text: "Click the download/export icon (usually a downward arrow or \"Export\" button).")
            HelpStep(number: 4, text: "Select CSV format and save the file.")
            HelpStep(number: 5, text: "Import the CSV into Dojix via drag-and-drop or file picker.")

            HelpSubtitle("How to Export from cTrader Web")
            HelpStep(number: 1, text: "Log in to your cTrader Web account.")
            HelpStep(number: 2, text: "Navigate to History > Deals or Trade History.")
            HelpStep(number: 3, text: "Set date range and click Export/Download as CSV.")
            HelpStep(number: 4, text: "Import into Dojix.")

            HelpSubtitle("Expected Columns")
            HelpParagraph("cTrader CSV exports typically include: Position ID, Symbol, Direction, Volume (lots), Entry Time, Entry Price, Close Time, Close Price, Stop Loss, Take Profit, Commission, Swap, Net Profit, Pips.")

            HelpTip("cTrader provides excellent data quality with pips and commission already calculated. This makes for very accurate Dojix analytics.")

            HelpSubtitle("cTrader Copy / Prop Firms")
            HelpParagraph("If you're trading through a prop firm that uses cTrader (e.g., FTMO, FundedNext), the export process is the same. Some prop firms also provide their own history download — use whichever gives more detail.")
        }
    }
}

// MARK: - TradingView

struct HelpImportTradingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Import from TradingView")
            HelpParagraph("TradingView supports paper trading and broker-connected trading. You can export your trade history from both.")

            HelpSubtitle("Paper Trading Export")
            HelpStep(number: 1, text: "Open TradingView and go to the Bottom Panel > Trading Panel.")
            HelpStep(number: 2, text: "Click the \"History\" tab to see your closed paper trades.")
            HelpStep(number: 3, text: "Click the gear/settings icon and select \"Export trade list\" or right-click > Export.")
            HelpStep(number: 4, text: "Save as CSV and import into Dojix.")

            HelpSubtitle("Broker-Connected Trading")
            HelpParagraph("If you trade through a broker connected to TradingView (e.g., OANDA, Forex.com), your trade history is stored by the broker. Export directly from your broker's platform instead — it will have more detailed data.")

            HelpSubtitle("Strategy Tester / Backtests")
            HelpStep(number: 1, text: "After running a Pine Script strategy, go to the Strategy Tester panel.")
            HelpStep(number: 2, text: "Click the \"List of Trades\" tab.")
            HelpStep(number: 3, text: "Click the export icon to download as CSV.")
            HelpStep(number: 4, text: "Import into Dojix to analyze your backtest results.")

            HelpSubtitle("Expected Columns")
            HelpParagraph("TradingView exports vary by source. Common columns include: Trade #, Type (Long/Short), Signal, Date/Time, Price, Contracts/Lots, Profit, Cumulative Profit, Run-up, Drawdown.")
        }
    }
}

// MARK: - OANDA

struct HelpImportOANDA: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Import from OANDA")
            HelpParagraph("OANDA provides detailed trade history through their fxTrade platform and web portal.")

            HelpSubtitle("How to Export from OANDA Web Portal")
            HelpStep(number: 1, text: "Log in to your OANDA account at fxtrade.oanda.com.")
            HelpStep(number: 2, text: "Navigate to My Account > Activity > Trade History or Transaction History.")
            HelpStep(number: 3, text: "Set your date range.")
            HelpStep(number: 4, text: "Click \"Download\" or \"Export\" and select CSV format.")
            HelpStep(number: 5, text: "Import the CSV into Dojix.")

            HelpSubtitle("How to Export from fxTrade Desktop")
            HelpStep(number: 1, text: "Open OANDA fxTrade desktop platform.")
            HelpStep(number: 2, text: "Go to Account > Trade History.")
            HelpStep(number: 3, text: "Set date range and click Export.")
            HelpStep(number: 4, text: "Save as CSV and import into Dojix.")

            HelpSubtitle("Expected Columns")
            HelpParagraph("OANDA exports typically include: Transaction ID, Instrument (pair), Type (buy/sell), Units, Open Time, Open Price, Close Time, Close Price, P/L, Financing (swap), Commission.")

            HelpTip("OANDA uses \"units\" instead of lots. Dojix converts automatically: 100,000 units = 1.0 standard lot, 10,000 = 0.1 mini lot, 1,000 = 0.01 micro lot.")
        }
    }
}

// MARK: - Interactive Brokers

struct HelpImportIB: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Import from Interactive Brokers")
            HelpParagraph("Interactive Brokers (IBKR) provides detailed trade reports through their Client Portal and Flex Query system.")

            HelpSubtitle("Option A: Activity Statement (Simple)")
            HelpStep(number: 1, text: "Log in to Client Portal at portal.interactivebrokers.com.")
            HelpStep(number: 2, text: "Go to Performance & Reports > Statements.")
            HelpStep(number: 3, text: "Select \"Activity\" statement type and choose your date range.")
            HelpStep(number: 4, text: "Choose CSV format and download.")
            HelpStep(number: 5, text: "The downloaded file may contain multiple sections. Look for the \"Trades\" section.")
            HelpStep(number: 6, text: "Import into Dojix.")

            HelpSubtitle("Option B: Flex Query (Advanced)")
            HelpParagraph("Flex Queries give you more control over which fields to export:")
            HelpStep(number: 1, text: "In Client Portal, go to Performance & Reports > Flex Queries.")
            HelpStep(number: 2, text: "Create a new Flex Query for \"Trades\" with fields: TradeID, Symbol, Side, Quantity, TradeDate, TradeTime, TradePrice, ClosePrice, Commission, NetCash, CurrencyPrimary.")
            HelpStep(number: 3, text: "Run the query and download as CSV.")
            HelpStep(number: 4, text: "Import into Dojix.")

            HelpSubtitle("Expected Columns")
            HelpParagraph("IB exports typically include: TradeID, Symbol, Date/Time, Quantity, T.Price (trade price), C.Price (close price), Proceeds, Comm/Fee, Realized P/L, Code.")

            HelpWarning("IB uses negative quantity for sell/short trades and positive for buy/long. Dojix handles this conversion automatically.")
        }
    }
}

// MARK: - Thinkorswim

struct HelpImportThinkorswim: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Import from Thinkorswim")
            HelpParagraph("Thinkorswim (by Schwab, formerly TD Ameritrade) provides trade history export through the platform's account statement.")

            HelpSubtitle("How to Export")
            HelpStep(number: 1, text: "Open Thinkorswim desktop platform.")
            HelpStep(number: 2, text: "Go to Monitor > Account Statement.")
            HelpStep(number: 3, text: "Set your date range at the top.")
            HelpStep(number: 4, text: "Scroll down to the \"Trade History\" section.")
            HelpStep(number: 5, text: "Right-click on the trade history table and select \"Export to File\" or \"Copy to Clipboard\".")
            HelpStep(number: 6, text: "If copying to clipboard, paste into a spreadsheet and save as CSV.")
            HelpStep(number: 7, text: "Import the CSV into Dojix.")

            HelpSubtitle("Alternative: Web Export")
            HelpStep(number: 1, text: "Log in to tdameritrade.com (or schwab.com).")
            HelpStep(number: 2, text: "Navigate to Accounts > History & Statements.")
            HelpStep(number: 3, text: "Select \"Transaction History\" and filter for trades.")
            HelpStep(number: 4, text: "Download as CSV.")

            HelpSubtitle("Expected Columns")
            HelpParagraph("Thinkorswim exports include: Exec Time, Side (BOT/SLD), Qty, Symbol, Price, Net Price, Order Type, Commission.")

            HelpTip("Thinkorswim uses \"BOT\" for buy and \"SLD\" for sell. Dojix recognizes both formats.")
        }
    }
}

// MARK: - NinjaTrader

struct HelpImportNinjaTrader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpTitle("Import from NinjaTrader")
            HelpParagraph("NinjaTrader is popular for futures and forex trading. You can export trade performance reports as CSV.")

            HelpSubtitle("How to Export")
            HelpStep(number: 1, text: "Open NinjaTrader 8.")
            HelpStep(number: 2, text: "Go to the Control Center > New > Trade Performance.")
            HelpStep(number: 3, text: "In the Trade Performance window, select your account and date range.")
            HelpStep(number: 4, text: "Click the \"Executions\" or \"Trades\" tab to see individual trades.")
            HelpStep(number: 5, text: "Right-click on the data grid and select \"Export\" > \"CSV\".")
            HelpStep(number: 6, text: "Save the file and import into Dojix.")

            HelpSubtitle("Alternative: Account Data Export")
            HelpStep(number: 1, text: "In NinjaTrader, go to Tools > Account Data.")
            HelpStep(number: 2, text: "Select \"Orders\" or \"Executions\".")
            HelpStep(number: 3, text: "Export as CSV.")

            HelpSubtitle("Expected Columns")
            HelpParagraph("NinjaTrader exports typically include: Trade #, Instrument, Market Position (Long/Short), Quantity, Entry Time, Entry Price, Exit Time, Exit Price, Profit, Commission, MAE, MFE.")

            HelpTip("NinjaTrader includes MAE and MFE in its exports, which gives Dojix more data to work with for trade quality analysis and grading.")
        }
    }
}
