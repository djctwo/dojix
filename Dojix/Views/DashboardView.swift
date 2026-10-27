import SwiftUI
import Charts
import AppKit

struct DashboardView: View {
    @Bindable var viewModel: DashboardViewModel
    let category: DashboardViewModel.DashboardCategory
    @Environment(\.appState) private var appState
    @AppStorage("dashboard_beginner_mode") private var isBeginnerMode = false
    @AppStorage("show_first_look_banner") private var showFirstLookBanner = false

    var body: some View {
        Group {
            if viewModel.trades.isEmpty {
                EmptyStateView(
                    icon: "chart.bar.xaxis",
                    title: "No Data Yet",
                    message: "Import trades to see your portfolio dashboard with equity curve, metrics, and edge breakdowns.",
                    actionTitle: "Go to Import"
                ) {
                    appState.selectedTab = .importTrades
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if isBeginnerMode && (category == .all || category == .overview) {
                            essentialContent
                        } else {
                            switch category {
                            case .all:
                                allContent
                            case .overview:
                                overviewContent
                            case .timing:
                                timingContent
                            case .sessions:
                                sessionsContent
                            case .pairs:
                                pairsContent
                            case .risk:
                                riskContent
                            case .behavioral:
                                behavioralContent
                            case .advanced:
                                advancedContent
                            case .propFirm:
                                propFirmContent
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle(category == .overview ? "Dashboard" : category.rawValue)
        .onReceive(NotificationCenter.default.publisher(for: .exportPDF)) { _ in
            exportDashboardPDF()
        }
        .toolbar {
            if !viewModel.trades.isEmpty || viewModel.selectedSymbol != nil {
                // Beginner/Expert toggle
                ToolbarItem(placement: .automatic) {
                    Picker("View", selection: $isBeginnerMode) {
                        Text("Essential").tag(true)
                        Text("All Analytics").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                ToolbarItem {
                    Picker("Pair", selection: $viewModel.selectedSymbol) {
                        Text("All Pairs").tag(nil as String?)
                        ForEach(viewModel.availableSymbols, id: \.self) { symbol in
                            Text(symbol).tag(symbol as String?)
                        }
                    }
                    .frame(width: 110)
                }
                ToolbarItem {
                    Picker("Period", selection: $viewModel.selectedDateRange) {
                        ForEach(DashboardViewModel.DateRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .frame(width: 130)
                }
                ToolbarItem {
                    Menu {
                        Button {
                            exportDashboardPDF()
                        } label: {
                            Label("Export PDF", systemImage: "doc.richtext")
                        }
                        Button {
                            exportDashboardCSV()
                        } label: {
                            Label("Export CSV", systemImage: "tablecells")
                        }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                            .font(.smallText)
                    }
                }
            }
        }
    }

    // MARK: - Essential Content (beginner mode — reduced cognitive load)

    @ViewBuilder
    private var essentialContent: some View {
        // First Look banner — one-time celebration after first import
        if showFirstLookBanner {
            firstLookBanner
        }

        // Daily Brief — top 3 actionable signals in plain English
        DailyBrief(trades: viewModel.trades, metrics: viewModel.metrics)

        // Key metrics with tooltips already attached
        metricsGrid

        // Equity curve — visual account health
        CollapsibleSection(title: "Account Growth", icon: "chart.line.uptrend.xyaxis", storageKey: "dash_equity_essential", defaultExpanded: true) {
            equityCurveChart
        }

        // Edge breakdowns — where you make/lose money
        CollapsibleSection(title: "Where You Make & Lose Money", icon: "target", storageKey: "dash_edge_essential", defaultExpanded: true) {
            edgeBreakdowns
        }

        // Gentle prompt to explore more
        HStack(spacing: 8) {
            Image(systemName: "lightbulb")
                .foregroundStyle(Color.accent)
            Text("Switch to \"All Analytics\" in the toolbar (or press \u{2318}\u{21E7}E) to explore 66 charts and breakdowns including heatmaps, Monte Carlo simulation, and more.")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(12)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.borderCard, lineWidth: 1)
        )
    }

    // MARK: - First Look Banner

    private var firstLookBanner: some View {
        let tradeCount = viewModel.trades.count
        let bestSession = viewModel.edgeBySession.max(by: { $0.profit < $1.profit })
        let pnlDirection = viewModel.metrics.totalProfit >= 0 ? "up" : "down"
        let pnlAmount = abs(viewModel.metrics.totalProfit).asCurrency

        return HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(Color.accent)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(tradeCount) trades imported — your first look")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)

                Group {
                    if let best = bestSession, best.profit > 0 {
                        Text("You're \(pnlDirection) \(pnlAmount) overall. Best session: \(best.label) (+\(best.profit.asCurrency)). Click any trade in Journal to see its full breakdown.")
                    } else {
                        Text("You're \(pnlDirection) \(pnlAmount) overall. Click any trade in Journal to see its full breakdown.")
                    }
                }
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            Button {
                withAnimation {
                    showFirstLookBanner = false
                    UserDefaults.standard.set(true, forKey: "has_seen_first_look")
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.accentDim)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accent.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - All Content (original full dashboard)

    @ViewBuilder
    private var allContent: some View {
        overviewContent
        timingContent
        sessionsContent
        pairsContent
        riskContent
        behavioralContent
        advancedContent
        propFirmContent
    }

    // MARK: - Overview (what matters first)

    @ViewBuilder
    private var overviewContent: some View {
        // Daily Brief — top 3 actionable signals, always visible
        DailyBrief(trades: viewModel.trades, metrics: viewModel.metrics)

        // Key metrics — always visible
        metricsGrid

        // Prop firm tracker
        PropFirmTracker(trades: viewModel.trades)

        // Performance — collapsible
        CollapsibleSection(title: "Performance", icon: "chart.line.uptrend.xyaxis", storageKey: "dash_perf", defaultExpanded: true) {
            HStack(spacing: 16) {
                SessionRankingCard(trades: viewModel.trades)
                StreakCard(trades: viewModel.trades)
            }
            PerformanceSummary(trades: viewModel.trades)
            PeriodComparison(trades: viewModel.trades)
        }

        // Charts — collapsible
        CollapsibleSection(title: "Charts", icon: "chart.xyaxis.line", storageKey: "dash_charts") {
            equityCurveChart
            DrawdownChart(trades: viewModel.trades)
            MonthlyReturns(trades: viewModel.trades)
            WeeklyHeatmap(trades: viewModel.trades)
        }

        // Edge breakdowns — collapsible
        CollapsibleSection(title: "Edge Breakdown", icon: "target", storageKey: "dash_edge") {
            edgeBreakdowns
        }
    }

    // MARK: - Timing (when you trade)

    @ViewBuilder
    private var timingContent: some View {
        TradeCalendar(trades: viewModel.trades)
        HourlyPnLChart(trades: viewModel.trades)
        equalHeightRow {
            DayOfWeekChart(trades: viewModel.trades)
        } right: {
            DurationAnalysis(trades: viewModel.trades)
        }
        TradeTimeHeatmap(trades: viewModel.trades)
    }

    // MARK: - Sessions (session-level edge)

    @ViewBuilder
    private var sessionsContent: some View {
        equalHeightRow {
            SessionHeatmap(trades: viewModel.trades)
        } right: {
            RMultipleChart(trades: viewModel.trades)
        }
        equalHeightRow {
            SessionIntelligence(trades: viewModel.trades)
        } right: {
            SequenceAnalysis(trades: viewModel.trades)
        }
        StreakTimeline(trades: viewModel.trades)
        // Optimization analytics
        KillZoneOptimizer(trades: viewModel.trades)
        WhatToCutAdvisor(trades: viewModel.trades)
    }

    // MARK: - Pairs (what/how you trade)

    @ViewBuilder
    private var pairsContent: some View {
        equalHeightRow {
            WinLossDistribution(trades: viewModel.trades)
        } right: {
            PairAnalytics(trades: viewModel.trades)
        }
        equalHeightRow {
            LotSizeAnalysis(trades: viewModel.trades)
        } right: {
            MAEMFEChart(trades: viewModel.trades)
        }
        equalHeightRow {
            DirectionalEdge(trades: viewModel.trades)
        } right: {
            SlippageAnalysis(trades: viewModel.trades)
        }
    }

    // MARK: - Risk (risk management)

    @ViewBuilder
    private var riskContent: some View {
        equalHeightRow {
            RiskOfRuin(trades: viewModel.trades)
        } right: {
            BehavioralAnalytics(trades: viewModel.trades)
        }
        MonteCarloSimulation(trades: viewModel.trades)
        DrawdownRecovery(trades: viewModel.trades)
        equalHeightRow {
            GrowthProjection(trades: viewModel.trades, metrics: viewModel.metrics)
        } right: {
            PositionSizer(trades: viewModel.trades, metrics: viewModel.metrics)
        }
        ExpectancyCurve(trades: viewModel.trades, metrics: viewModel.metrics)
        equalHeightRow {
            ExitAnalysis(trades: viewModel.trades)
        } right: {
            CommissionAnalytics(trades: viewModel.trades)
        }
        // Net currency exposure
        NetCurrencyExposure(trades: viewModel.trades)
    }

    // MARK: - Behavioral (discipline & psychology)

    @ViewBuilder
    private var behavioralContent: some View {
        equalHeightRow {
            GradeDistribution(trades: viewModel.trades)
        } right: {
            ConsistencyScore(trades: viewModel.trades)
        }
        equalHeightRow {
            EmotionalAnalytics(trades: viewModel.trades)
        } right: {
            ChecklistAnalytics(trades: viewModel.trades)
        }
        ImprovementTracker(trades: viewModel.trades)
        TradeComparison(trades: viewModel.trades)
        PlaybookCatalog(trades: viewModel.trades)
    }

    // MARK: - Advanced (deep dives)

    @ViewBuilder
    private var advancedContent: some View {
        CalendarCorrelation(trades: viewModel.trades)
        EventImpactProfiler(trades: viewModel.trades)
        equalHeightRow {
            BenchmarkComparison(trades: viewModel.trades, metrics: viewModel.metrics)
        } right: {
            PairCorrelation(trades: viewModel.trades)
        }
        DataQuality(trades: viewModel.trades)
        ShareableSummary(trades: viewModel.trades, metrics: viewModel.metrics)
        // Deep analysis
        equalHeightRow {
            EdgeDecayMonitor(trades: viewModel.trades)
        } right: {
            TimeToMFEAnalysis(trades: viewModel.trades)
        }
        // Strategy version control
        StrategyCheckpoints(
            trades: viewModel.trades,
            checkpoints: viewModel.checkpoints,
            onAdd: { viewModel.addCheckpoint($0) },
            onDelete: { viewModel.deleteCheckpoint(id: $0) }
        )
    }

    // MARK: - Prop Firm

    @ViewBuilder
    private var propFirmContent: some View {
        PropFirmTracker(trades: viewModel.trades)
    }

    // MARK: - Equal Height Row

    private func equalHeightRow<L: View, R: View>(
        @ViewBuilder left: () -> L,
        @ViewBuilder right: () -> R
    ) -> some View {
        EqualHeightHStack(spacing: 16) {
            StretchingCard { left() }
            StretchingCard { right() }
        }
    }

    // MARK: - Export

    private func exportDashboardPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Dojix_Dashboard_\(Date().formatted(.dateTime.year().month().day())).pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let exporter = PDFExporter()
        do {
            try exporter.exportDashboard(
                trades: viewModel.trades,
                metrics: viewModel.metrics,
                edgeBySession: viewModel.edgeBySession,
                edgeByHour: viewModel.edgeByHour,
                edgeByPair: viewModel.edgeByPair,
                edgeByDay: viewModel.edgeByDay,
                to: url
            )
            appState.showToast(.success, "Dashboard exported to PDF")
        } catch {
            appState.showToast(.error, error.friendlyMessage)
        }
    }

    private func exportDashboardCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "Dojix_Trades_\(Date().formatted(.dateTime.year().month().day())).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let exporter = CSVExporter()
        do {
            try exporter.export(trades: viewModel.trades, to: url)
            appState.showToast(.success, "CSV exported with \(viewModel.trades.count) trades")
        } catch {
            appState.showToast(.error, error.friendlyMessage)
        }
    }


    // MARK: - Key Metrics Grid

    private var metricsGrid: some View {
        VStack(spacing: 8) {
            // Primary KPI row — 4 cards
            HStack(spacing: 12) {
                MetricCard(
                    title: "Total P&L",
                    value: viewModel.metrics.totalProfit.asCurrency,
                    subtitle: "\(viewModel.metrics.totalTrades) trades",
                    valueColor: Color.forPnL(viewModel.metrics.totalProfit),
                    tooltip: "Net profit/loss across all filtered trades. Green = profitable, red = losing."
                )
                MetricCard(
                    title: "Win Rate",
                    value: viewModel.metrics.winRate.asPercent,
                    subtitle: "\(viewModel.metrics.wins)W / \(viewModel.metrics.losses)L",
                    valueColor: .semanticAmber,
                    tooltip: "Percentage of trades that closed in profit. Above 50% is generally good, but depends on your R-multiple."
                )
                MetricCard(
                    title: "Profit Factor",
                    value: viewModel.metrics.profitFactor.asProfitFactor,
                    subtitle: "Gross: \(viewModel.metrics.grossProfit.asCompactCurrency)",
                    valueColor: .semanticBlue,
                    tooltip: "Gross profit divided by gross loss. Above 1.5 is strong. Below 1.0 means you're losing money overall."
                )
                MetricCard(
                    title: "Expectancy",
                    value: viewModel.metrics.expectancy.asCurrency,
                    subtitle: "per trade",
                    valueColor: .semanticPurple,
                    tooltip: "Expected dollar value per trade: (Win% x Avg Win) - (Loss% x Avg Loss). Positive = profitable edge."
                )
            }

            // Secondary KPI row — 5 smaller cards
            HStack(spacing: 8) {
                MetricCardSmall(
                    title: "Avg Win",
                    value: viewModel.metrics.averageWin.asCurrency,
                    valueColor: .semanticGreen,
                    tooltip: "Average profit on winning trades."
                )
                MetricCardSmall(
                    title: "Avg Loss",
                    value: (-viewModel.metrics.averageLoss).asCurrency,
                    valueColor: .semanticRed,
                    tooltip: "Average loss on losing trades. Compare to Avg Win — ideally your wins are 1.5-2x larger."
                )
                MetricCardSmall(
                    title: "Max DD",
                    value: viewModel.metrics.maxDrawdown.asCurrency,
                    valueColor: .semanticAmber,
                    tooltip: "Maximum drawdown — the largest peak-to-trough decline in your equity curve."
                )
                MetricCardSmall(
                    title: "Sharpe",
                    value: String(format: "%.2f", viewModel.metrics.sharpeRatio),
                    valueColor: .semanticBlue,
                    tooltip: "Risk-adjusted return. Above 1.0 is good, above 2.0 is excellent. Measures consistency relative to volatility."
                )
                MetricCardSmall(
                    title: "Avg R",
                    value: viewModel.metrics.averageRMultiple.asRMultiple,
                    valueColor: .semanticPurple,
                    tooltip: "Average R-multiple per trade. R = profit as multiples of initial risk (stop distance). Above 0.5R is strong."
                )
            }
        }
    }

    // MARK: - Equity Curve

    private var equityCurveChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Equity Curve")
                .font(.headline)

            if viewModel.equityCurve.isEmpty {
                emptyState("Import trades to see your equity curve")
            } else {
                Chart {
                    ForEach(Array(viewModel.equityCurve.enumerated()), id: \.offset) { _, point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("P&L", point.cumulative)
                        )
                        .foregroundStyle(Color.semanticBlue)

                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("P&L", point.cumulative)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.semanticBlue.opacity(0.25), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(v.asCompactCurrency)
                            }
                        }
                    }
                }
                .frame(height: 250)
            }
        }
        .padding(16)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.borderCard, lineWidth: 1)
        )
        .accentTopBar()
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Edge Breakdowns

    private var edgeBreakdowns: some View {
        VStack(spacing: 16) {
            equalHeightRow {
                edgeCard(title: "P&L by Session", data: viewModel.edgeBySession)
            } right: {
                edgeCard(title: "P&L by Pair", data: viewModel.edgeByPair)
            }
            equalHeightRow {
                edgeCard(title: "P&L by Hour", data: viewModel.edgeByHour.prefix(10).map { $0 })
            } right: {
                edgeCard(title: "P&L by Day", data: viewModel.edgeByDay)
            }
        }
    }

    private func edgeCard(title: String, data: [MetricsCalculator.EdgeBreakdown]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            if data.isEmpty {
                emptyState("No data yet")
            } else {
                ForEach(data) { item in
                    HStack {
                        Text(item.label)
                            .font(.smallText)
                            .frame(width: 70, alignment: .leading)
                        ProgressView(value: normalizedProfit(item.profit, in: data), total: 1.0)
                            .tint(Color.forPnL(item.profit))
                        Text(item.profit.asCurrency)
                            .font(.monoSubtitle)
                            .foregroundStyle(Color.forPnL(item.profit))
                            .frame(width: 70, alignment: .trailing)
                        Text("\(item.tradeCount)t")
                            .font(.smallText)
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: 25, alignment: .trailing)
                    }
                }
            }
        }
        .padding(16)
    }

    private func normalizedProfit(_ profit: Double, in data: [MetricsCalculator.EdgeBreakdown]) -> Double {
        let maxAbs = data.map { abs($0.profit) }.max() ?? 1
        guard maxAbs > 0 else { return 0 }
        return abs(profit) / maxAbs
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.smallText)
            .foregroundStyle(Color.textTertiary)
            .frame(maxWidth: .infinity, minHeight: 100)
    }
}
