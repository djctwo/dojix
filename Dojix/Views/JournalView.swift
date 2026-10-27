import SwiftUI

struct JournalView: View {
    @Bindable var viewModel: JournalViewModel
    @Environment(\.appState) private var appState
    @State private var selectedTrade: Trade?
    @State private var showReplay: Bool = false
    @State private var sortOrder = [KeyPathComparator(\Trade.closeTime, order: .reverse)]
    @SceneStorage("journalColumnConfig") private var columnCustomization: TableColumnCustomization<Trade>

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.filteredTrades.isEmpty && viewModel.searchText.isEmpty {
                EmptyStateView(
                    icon: "list.bullet.rectangle",
                    title: "No Trades Yet",
                    message: "Import a StrategyAnalytics CSV to see your trade journal.",
                    actionTitle: "Go to Import"
                ) {
                    appState.selectedTab = .importTrades
                }
            } else {
                toolbar
                performanceSummary
                Divider()
                tradeTable
            }
        }
        .navigationTitle("Trade Journal")
        .sheet(item: $selectedTrade) { trade in
            TradeDetailView(trade: trade)
        }
        .sheet(isPresented: $showReplay) {
            TradeReplayView(trades: viewModel.filteredTrades)
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportPDF)) { _ in
            exportPDF()
        }
    }

    // MARK: - Sorted Trades

    private var sortedTrades: [Trade] {
        viewModel.filteredTrades.sorted(using: sortOrder)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.textSecondary)
                TextField("Search trades...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(6)
            .background(Color.bgContent)
            .clipShape(RoundedRectangle(cornerRadius: 12))
           .overlay(
               RoundedRectangle(cornerRadius: 12)
                   .stroke(Color.borderCard, lineWidth: 1)
           )
            .frame(maxWidth: 200)

            // Symbol filter
            Picker("Pair", selection: $viewModel.selectedSymbolFilter) {
                Text("All Pairs").tag(nil as String?)
                ForEach(viewModel.uniqueSymbols, id: \.self) { symbol in
                    Text(symbol).tag(symbol as String?)
                }
            }
            .frame(width: 120)

            // Session filter
            Picker("Session", selection: $viewModel.selectedSessionFilter) {
                Text("All Sessions").tag(nil as TradingSession?)
                ForEach(TradingSession.allCases) { session in
                    Text(session.displayName).tag(session as TradingSession?)
                }
            }
            .frame(width: 130)

            // Direction filter
            Picker("Direction", selection: $viewModel.selectedDirectionFilter) {
                Text("All Dirs").tag(nil as TradeDirection?)
                Text("BUY").tag(TradeDirection.buy as TradeDirection?)
                Text("SELL").tag(TradeDirection.sell as TradeDirection?)
            }
            .frame(width: 90)

            // Date range
            Picker("Range", selection: $viewModel.selectedDateRange) {
                ForEach(JournalViewModel.DateRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .frame(width: 120)

            Spacer()

            // Stats
            Text("\(viewModel.filteredTrades.count) trades")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
            Text(viewModel.totalFilteredProfit.asCurrency)
                .font(.smallText)
                .fontWeight(.semibold)
                .foregroundStyle(Color.forPnL(viewModel.totalFilteredProfit))

            // Actions menu (export + replay)
            Menu {
                Button {
                    exportPDF()
                } label: {
                    Label("Export PDF", systemImage: "doc.richtext")
                }

                Button {
                    exportCSV()
                } label: {
                    Label("Export CSV", systemImage: "tablecells")
                }

                Divider()

                Button {
                    showReplay = true
                } label: {
                    Label("Trade Replay", systemImage: "play.circle")
                }
                .disabled(viewModel.filteredTrades.count < 2)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.smallText)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Performance Summary Strip

    private var performanceSummary: some View {
        let metrics = MetricsCalculator.calculate(from: viewModel.filteredTrades)
        return HStack(spacing: 20) {
            summaryItem("P&L", value: metrics.totalProfit.asCurrency, color: Color.forPnL(metrics.totalProfit), help: TradingTerms.pnl)
            summaryItem("Win Rate", value: metrics.winRate.asPercent, color: metrics.winRate >= 50 ? .semanticGreen : .semanticRed, help: TradingTerms.winRate)
            summaryItem("PF", value: metrics.profitFactor.asProfitFactor, color: metrics.profitFactor >= 1 ? .semanticGreen : .semanticRed, help: TradingTerms.profitFactor)
            summaryItem("Expect.", value: metrics.expectancy.asCurrency, color: Color.forPnL(metrics.expectancy), help: TradingTerms.expectancy)
            summaryItem("Avg R", value: metrics.averageRMultiple.asRMultiple, color: Color.forPnL(metrics.averageRMultiple), help: TradingTerms.avgR)
            if metrics.maxWinStreak > 0 {
                summaryItem("Streak", value: "\(metrics.currentStreak > 0 ? "+" : "")\(metrics.currentStreak)", color: Color.forPnL(Double(metrics.currentStreak)), help: TradingTerms.streak)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(Color.bgContent.opacity(0.5))
    }

    private func summaryItem(_ title: String, value: String, color: Color, help: String? = nil) -> some View {
        VStack(spacing: 1) {
            HStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textTertiary)
                if let help {
                    HelpTooltip(term: title, definition: help)
                }
            }
            Text(value)
                .font(.monoSubtitle)
                .fontWeight(.medium)
                .foregroundStyle(color)
        }
    }

    // MARK: - Trade Table

    private var portfolioMetrics: MetricsCalculator.PortfolioMetrics {
        MetricsCalculator.calculate(from: viewModel.filteredTrades)
    }

    private var cumulativePnLMap: [Int64: Double] {
        var cum = 0.0
        var map: [Int64: Double] = [:]
        let chronological = viewModel.filteredTrades.sorted { $0.closeTime < $1.closeTime }
        for trade in chronological {
            cum += trade.profitDouble
            map[trade.ticket] = cum
        }
        return map
    }

    private var tradeTable: some View {
        let metrics = portfolioMetrics
        let cumMap = cumulativePnLMap
        return Table(sortedTrades, sortOrder: $sortOrder, columnCustomization: $columnCustomization) {
            TableColumn("Close Time", value: \.closeTime) { trade in
                Button {
                    selectedTrade = trade
                } label: {
                    Text(trade.closeTime.tradeDisplayString)
                        .font(.monoSubtitle)
                }
                .buttonStyle(.plain)
                .contextMenu { tradeContextMenu(for: trade) }
            }
            .width(min: 90, ideal: 100)
            .customizationID("closeTime")

            TableColumn("Pair", value: \.symbol) { trade in
                PairLabel(symbol: trade.symbol)
                    .contextMenu { tradeContextMenu(for: trade) }
            }
            .width(min: 70, ideal: 80)
            .customizationID("pair")

            TableColumn("Dir", value: \.direction) { trade in
                DirectionLabel(direction: trade.direction)
                    .contextMenu { tradeContextMenu(for: trade) }
            }
            .width(min: 50, ideal: 55)
            .customizationID("direction")

            TableColumn("Lots", value: \.lots) { trade in
                Text(String(format: "%.2f", trade.lots))
                    .font(.monoSubtitle)
                    .contextMenu { tradeContextMenu(for: trade) }
            }
            .width(min: 40, ideal: 50)
            .customizationID("lots")

            TableColumn("P&L", value: \.netProfit) { trade in
                Text(trade.profitDouble.asCurrency)
                    .font(.monoSubtitle)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.forPnL(trade.netProfit))
                    .contextMenu { tradeContextMenu(for: trade) }
            }
            .width(min: 70, ideal: 80)
            .customizationID("pnl")

            TableColumn("Cum P&L") { trade in
                let cum = cumMap[trade.ticket] ?? 0
                Text(cum.asCompactCurrency)
                    .font(.monoSubtitle)
                    .foregroundStyle(Color.forPnL(cum))
                    .contextMenu { tradeContextMenu(for: trade) }
            }
            .width(min: 55, ideal: 65)
            .customizationID("cumPnl")

            TableColumn("R") { trade in
                Text(trade.rMultiple.asRMultiple)
                    .font(.monoSubtitle)
                    .foregroundStyle(Color.forPnL(trade.rMultiple))
                    .contextMenu { tradeContextMenu(for: trade) }
            }
            .width(min: 50, ideal: 55)
            .customizationID("rMultiple")

            TableColumn("Grade") { trade in
                let grade = TradeGrader.grade(trade, portfolioMetrics: metrics)
                GradeBadge(grade: grade)
                    .contextMenu { tradeContextMenu(for: trade) }
            }
            .width(min: 35, ideal: 40)
            .customizationID("grade")

            TableColumn("Session") { trade in
                SessionBadge(session: trade.session)
                    .contextMenu { tradeContextMenu(for: trade) }
            }
            .width(min: 75, ideal: 85)
            .customizationID("session")

            TableColumn("Hour", value: \.hour) { trade in
                Text("\(trade.hour):00")
                    .font(.monoSubtitle)
                    .contextMenu { tradeContextMenu(for: trade) }
            }
            .width(min: 40, ideal: 45)
            .customizationID("hour")
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func tradeContextMenu(for trade: Trade) -> some View {
        Button {
            selectedTrade = trade
        } label: {
            Label("View Details", systemImage: "info.circle")
        }

        Divider()

        Button {
            let summary = "\(trade.symbol) \(trade.direction) \(String(format: "%.2f", trade.lots)) lots — \(trade.profitDouble.asCurrency)"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(summary, forType: .string)
        } label: {
            Label("Copy Trade Summary", systemImage: "doc.on.doc")
        }

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(trade.profitDouble.asCurrency, forType: .string)
        } label: {
            Label("Copy P&L", systemImage: "dollarsign.circle")
        }
    }

    // MARK: - Export

    private func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Dojix_Journal_\(Date().formatted(.dateTime.year().month().day())).pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let metrics = MetricsCalculator.calculate(from: viewModel.filteredTrades)
        let exporter = PDFExporter()
        do {
            try exporter.exportJournal(trades: viewModel.filteredTrades, metrics: metrics, to: url)
            appState.showToast(.success, "PDF exported with \(viewModel.filteredTrades.count) trades")
        } catch {
            appState.showToast(.error, error.friendlyMessage)
        }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "Dojix_Trades_\(Date().formatted(.dateTime.year().month().day())).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let exporter = CSVExporter()
        do {
            try exporter.export(trades: viewModel.filteredTrades, to: url)
            appState.showToast(.success, "CSV exported with \(viewModel.filteredTrades.count) trades")
        } catch {
            appState.showToast(.error, error.friendlyMessage)
        }
    }

}

// MARK: - Identifiable Conformance for Pickers

extension TradingSession: Identifiable {
    public var id: String { rawValue }
}
