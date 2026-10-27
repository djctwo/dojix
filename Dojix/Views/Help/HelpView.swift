import SwiftUI

/// Comprehensive in-app help system with sidebar navigation
struct HelpView: View {
    @State private var selectedTopic: HelpTopic = .gettingStarted
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTopic) {
                Section("Basics") {
                    topicRow(.gettingStarted)
                    topicRow(.importingTrades)
                    topicRow(.exportingData)
                }
                Section("Features") {
                    topicRow(.journal)
                    topicRow(.dashboard)
                    topicRow(.edgeReport)
                    topicRow(.pulse)
                    topicRow(.tradeReplay)
                }
                Section("Analytics Guide") {
                    topicRow(.metricsExplained)
                    topicRow(.analyticsComponents)
                    topicRow(.aiAnalysis)
                }
                Section("Platform Import Guides") {
                    topicRow(.importMT5)
                    topicRow(.importMT4)
                    topicRow(.importCTrader)
                    topicRow(.importTradingView)
                    topicRow(.importOanda)
                    topicRow(.importInteractiveBrokers)
                    topicRow(.importThinkorswim)
                    topicRow(.importNinjaTrader)
                }
                Section("Settings & Security") {
                    topicRow(.settings)
                    topicRow(.appLock)
                    topicRow(.keyboardShortcuts)
                }
                Section("Reference") {
                    topicRow(.glossary)
                    topicRow(.faq)
                    topicRow(.troubleshooting)
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 200)
            .searchable(text: $searchText, prompt: "Search help")
        } detail: {
            ScrollView {
                selectedTopic.content
                    .padding(32)
                    .frame(maxWidth: 720, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            .background(Color.bgContent)
        }
        .frame(minWidth: 800, minHeight: 550)
    }

    private func topicRow(_ topic: HelpTopic) -> some View {
        Label(topic.title, systemImage: topic.icon)
            .tag(topic)
    }
}

// MARK: - Help Topics

enum HelpTopic: String, CaseIterable, Identifiable {
    case gettingStarted, importingTrades, exportingData
    case journal, dashboard, edgeReport, pulse, tradeReplay
    case metricsExplained, analyticsComponents, aiAnalysis
    case importMT5, importMT4, importCTrader, importTradingView
    case importOanda, importInteractiveBrokers, importThinkorswim, importNinjaTrader
    case settings, appLock, keyboardShortcuts
    case glossary, faq, troubleshooting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gettingStarted: "Getting Started"
        case .importingTrades: "Importing Trades"
        case .exportingData: "Exporting Data"
        case .journal: "Trade Journal"
        case .dashboard: "Dashboard"
        case .edgeReport: "Edge Report"
        case .pulse: "Pulse (Live Data)"
        case .tradeReplay: "Trade Replay"
        case .metricsExplained: "Metrics Explained"
        case .analyticsComponents: "Analytics Components"
        case .aiAnalysis: "AI Analysis"
        case .importMT5: "MetaTrader 5 (MT5)"
        case .importMT4: "MetaTrader 4 (MT4)"
        case .importCTrader: "cTrader"
        case .importTradingView: "TradingView"
        case .importOanda: "OANDA"
        case .importInteractiveBrokers: "Interactive Brokers"
        case .importThinkorswim: "Thinkorswim"
        case .importNinjaTrader: "NinjaTrader"
        case .settings: "Settings"
        case .appLock: "App Lock"
        case .keyboardShortcuts: "Keyboard Shortcuts"
        case .glossary: "Glossary"
        case .faq: "FAQ"
        case .troubleshooting: "Troubleshooting"
        }
    }

    var icon: String {
        switch self {
        case .gettingStarted: "star"
        case .importingTrades: "square.and.arrow.down"
        case .exportingData: "square.and.arrow.up"
        case .journal: "list.bullet.rectangle"
        case .dashboard: "chart.bar.xaxis"
        case .edgeReport: "target"
        case .pulse: "waveform.path.ecg"
        case .tradeReplay: "play.rectangle"
        case .metricsExplained: "function"
        case .analyticsComponents: "chart.dots.scatter"
        case .aiAnalysis: "brain"
        case .importMT5: "arrow.down.doc"
        case .importMT4: "arrow.down.doc"
        case .importCTrader: "arrow.down.doc"
        case .importTradingView: "arrow.down.doc"
        case .importOanda: "arrow.down.doc"
        case .importInteractiveBrokers: "arrow.down.doc"
        case .importThinkorswim: "arrow.down.doc"
        case .importNinjaTrader: "arrow.down.doc"
        case .settings: "gearshape"
        case .appLock: "lock.shield"
        case .keyboardShortcuts: "keyboard"
        case .glossary: "book"
        case .faq: "questionmark.circle"
        case .troubleshooting: "wrench.and.screwdriver"
        }
    }

    @ViewBuilder
    var content: some View {
        switch self {
        case .gettingStarted: HelpGettingStarted()
        case .importingTrades: HelpImportingTrades()
        case .exportingData: HelpExportingData()
        case .journal: HelpJournal()
        case .dashboard: HelpDashboard()
        case .edgeReport: HelpEdgeReport()
        case .pulse: HelpPulse()
        case .tradeReplay: HelpTradeReplay()
        case .metricsExplained: HelpMetrics()
        case .analyticsComponents: HelpAnalyticsComponents()
        case .aiAnalysis: HelpAIAnalysis()
        case .importMT5: HelpImportMT5()
        case .importMT4: HelpImportMT4()
        case .importCTrader: HelpImportCTrader()
        case .importTradingView: HelpImportTradingView()
        case .importOanda: HelpImportOANDA()
        case .importInteractiveBrokers: HelpImportIB()
        case .importThinkorswim: HelpImportThinkorswim()
        case .importNinjaTrader: HelpImportNinjaTrader()
        case .settings: HelpSettings()
        case .appLock: HelpAppLock()
        case .keyboardShortcuts: HelpKeyboardShortcuts()
        case .glossary: HelpGlossary()
        case .faq: HelpFAQ()
        case .troubleshooting: HelpTroubleshooting()
        }
    }
}
