import SwiftUI
import Charts
import AppKit

struct EdgeReportView: View {
    @Bindable var viewModel: EdgeReportViewModel
    @Environment(\.appState) private var appState

    var body: some View {
        ScrollView {
            if !viewModel.hasEnoughData {
                insufficientDataView
            } else {
                VStack(spacing: 24) {
                    headerSummary
                    aiAnalysisSection
                    edgeSections
                    biasAndVolatility
                    PostCloseAnalysis(trades: viewModel.trades)
                    TagAnalytics(trades: viewModel.trades)
                }
                .padding(20)
            }
        }
        .navigationTitle("Edge Report")
        .onReceive(NotificationCenter.default.publisher(for: .exportPDF)) { _ in
            if viewModel.hasEnoughData {
                exportEdgeReportPDF()
            }
        }
        .toolbar {
            if viewModel.hasEnoughData {
                ToolbarItem {
                    Button {
                        exportEdgeReportPDF()
                    } label: {
                        Label("Export PDF", systemImage: "square.and.arrow.up")
                            .font(.smallText)
                    }
                }
            }
        }
    }

    // MARK: - Export

    private func exportEdgeReportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Dojix_EdgeReport_\(Date().formatted(.dateTime.year().month().day())).pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let trades = viewModel.trades
        let metrics = viewModel.metrics
        let exporter = PDFExporter()
        do {
            try exporter.exportEdgeReport(
                trades: trades,
                metrics: metrics,
                edgeBySession: MetricsCalculator.edgeBySession(from: trades),
                edgeByHour: MetricsCalculator.edgeByHour(from: trades),
                edgeByPair: MetricsCalculator.edgeByPair(from: trades),
                edgeByDay: MetricsCalculator.edgeByDay(from: trades),
                to: url
            )
            appState.showToast(.success, "Edge Report exported to PDF")
        } catch {
            appState.showToast(.error, error.friendlyMessage)
        }
    }

    // MARK: - Insufficient Data

    private var insufficientDataView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 48))
                .foregroundStyle(Color.textTertiary)
            Text("Need More Data")
                .font(.title2)
                .fontWeight(.medium)
            Text("Import at least \(Configuration.minimumTradesForAnalysis) trades to generate your edge report.")
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            Text("\(viewModel.trades.count) / \(Configuration.minimumTradesForAnalysis) trades imported")
                .font(.smallText)
                .foregroundStyle(Color.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Header Summary

    private var headerSummary: some View {
        HStack(spacing: 16) {
            MetricCard(
                title: "Total P&L",
                value: viewModel.metrics.totalProfit.asCurrency,
                subtitle: "\(viewModel.metrics.totalTrades) trades analyzed",
                valueColor: Color.forPnL(viewModel.metrics.totalProfit),
                icon: "dollarsign.circle",
                tooltip: TradingTerms.pnl
            )
            MetricCard(
                title: "Win Rate",
                value: viewModel.metrics.winRate.asPercent,
                subtitle: "\(viewModel.metrics.wins)W / \(viewModel.metrics.losses)L",
                valueColor: viewModel.metrics.winRate >= 50 ? .semanticGreen : .semanticRed,
                icon: "target",
                tooltip: TradingTerms.winRate
            )
            MetricCard(
                title: "Profit Factor",
                value: viewModel.metrics.profitFactor.asProfitFactor,
                valueColor: viewModel.metrics.profitFactor >= 1 ? .semanticGreen : .semanticRed,
                icon: "chart.bar",
                tooltip: TradingTerms.profitFactor
            )
            MetricCard(
                title: "Expectancy",
                value: viewModel.metrics.expectancy.asCurrency,
                subtitle: "per trade",
                valueColor: Color.forPnL(viewModel.metrics.expectancy),
                icon: "function",
                tooltip: TradingTerms.expectancy
            )
        }
    }

    // MARK: - AI Analysis

    /// Whether the user has saved their own Anthropic API key
    private var hasAnthropicKey: Bool {
        !(KeychainHelper.anthropicAPIKey ?? "").isEmpty
    }

    private var aiAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("AI Recommendations", systemImage: "brain")
                    .font(.headline)
                Spacer()
                if viewModel.isAnalyzing {
                    ProgressView()
                        .controlSize(.small)
                    Text("Analyzing...")
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                } else if hasAnthropicKey {
                    Button {
                        Task { await viewModel.runAIAnalysis() }
                    } label: {
                        Label("Run Analysis", systemImage: "play.fill")
                    }
                    .controlSize(.small)
                    .disabled(!viewModel.hasEnoughData)
                } else {
                    Button {
                        appState.selectedTab = .settings
                    } label: {
                        Label("Add Your API Key", systemImage: "key")
                    }
                    .controlSize(.small)
                }
            }

            Text(hasAnthropicKey
                 ? "Optional. Clicking Run Analysis sends a summary of your trades (totals, and P&L and win rate by session, hour, day, pair, bias and volatility) to Anthropic using your own API key, billed to your Anthropic account. Individual trades, tickets and notes are not sent. Nothing is sent unless you click."
                 : "Optional and off by default. To use it, add your own Anthropic API key in Settings. Dojix never sends anything to an AI service without your key and a click on Run Analysis.")
                .font(.smallText)
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if let error = viewModel.aiError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.smallText)
                        .foregroundStyle(Color.semanticRed)
                }
                .padding(8)
                .background(Color.semanticRed.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
           .overlay(
               RoundedRectangle(cornerRadius: 12)
                   .stroke(Color.borderCard, lineWidth: 1)
           )
            }

            if let recommendations = viewModel.aiRecommendations {
                Text(recommendations)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(12)
                    .background(Color.bgContent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
           .overlay(
               RoundedRectangle(cornerRadius: 12)
                   .stroke(Color.borderCard, lineWidth: 1)
           )
            }
        }
        .padding(16)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
   .overlay(
       RoundedRectangle(cornerRadius: 12)
           .stroke(Color.borderCard, lineWidth: 1)
   )
    }

    // MARK: - Edge Sections

    private var edgeSections: some View {
        VStack(spacing: 20) {
            // By Session
            edgePairSection(
                title: "By Session",
                icon: "clock",
                makers: viewModel.topMakersBySession,
                losers: viewModel.topLosersBySession
            )

            // By Hour
            edgePairSection(
                title: "By Hour",
                icon: "clock.badge",
                makers: viewModel.topMakersByHour,
                losers: viewModel.topLosersByHour
            )

            // By Pair
            edgePairSection(
                title: "By Pair",
                icon: "arrow.left.arrow.right",
                makers: viewModel.topMakersByPair,
                losers: viewModel.topLosersByPair
            )

            // By Day
            edgePairSection(
                title: "By Day of Week",
                icon: "calendar",
                makers: viewModel.topMakersByDay,
                losers: viewModel.topLosersByDay
            )
        }
    }

    private func edgePairSection(
        title: String,
        icon: String,
        makers: [MetricsCalculator.EdgeBreakdown],
        losers: [MetricsCalculator.EdgeBreakdown]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)

            HStack(alignment: .top, spacing: 16) {
                edgeColumn(
                    heading: "Where You Make Money",
                    items: makers,
                    accentColor: .semanticGreen
                )
                edgeColumn(
                    heading: "Where You Lose Money",
                    items: losers,
                    accentColor: .semanticRed
                )
            }
        }
        .padding(16)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
   .overlay(
       RoundedRectangle(cornerRadius: 12)
           .stroke(Color.borderCard, lineWidth: 1)
   )
    }

    private func edgeColumn(
        heading: String,
        items: [MetricsCalculator.EdgeBreakdown],
        accentColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(heading)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(accentColor)

            if items.isEmpty {
                Text("None")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack {
                        Text("#\(index + 1)")
                            .font(.smallText)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: 22)
                        Text(item.label)
                            .font(.monoSubtitle)
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(item.profit.asCurrency)
                                .font(.monoSubtitle)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.forPnL(item.profit))
                            Text("\(item.tradeCount)t · \(item.winRate.asPercent)")
                                .font(.smallText)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    .padding(.vertical, 2)
                    if index < items.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Bias & Volatility

    private var biasAndVolatility: some View {
        HStack(alignment: .top, spacing: 16) {
            // Bias alignment
            VStack(alignment: .leading, spacing: 12) {
                Label("Bias Alignment", systemImage: "arrow.up.arrow.down")
                    .font(.headline)

                if viewModel.biasSummary.isEmpty {
                    Text("No data")
                        .font(.smallText)
                        .foregroundStyle(Color.textTertiary)
                } else {
                    biasChart
                    ForEach(viewModel.biasSummary) { item in
                        HStack {
                            BiasBadge(bias: BiasAlignment(rawValue: item.label) ?? .neutral)
                            Spacer()
                            Text(item.profit.asCurrency)
                                .font(.monoSubtitle)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.forPnL(item.profit))
                            Text("\(item.tradeCount)t")
                                .font(.smallText)
                                .foregroundStyle(Color.textSecondary)
                                .frame(width: 30, alignment: .trailing)
                        }
                    }
                }
            }
            .padding(16)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))

           .overlay(

               RoundedRectangle(cornerRadius: 12)

                   .stroke(Color.borderCard, lineWidth: 1)

           )

            // Volatility regime
            VStack(alignment: .leading, spacing: 12) {
                Label("Volatility Regime", systemImage: "waveform.path.ecg")
                    .font(.headline)

                if viewModel.volRegimeSummary.isEmpty {
                    Text("No data")
                        .font(.smallText)
                        .foregroundStyle(Color.textTertiary)
                } else {
                    volChart
                    ForEach(viewModel.volRegimeSummary) { item in
                        HStack {
                            VolatilityBadge(regime: VolatilityRegime(rawValue: item.label) ?? .med)
                            Spacer()
                            Text(item.profit.asCurrency)
                                .font(.monoSubtitle)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.forPnL(item.profit))
                            Text("\(item.tradeCount)t")
                                .font(.smallText)
                                .foregroundStyle(Color.textSecondary)
                                .frame(width: 30, alignment: .trailing)
                        }
                    }
                }
            }
            .padding(16)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
       .overlay(
           RoundedRectangle(cornerRadius: 12)
               .stroke(Color.borderCard, lineWidth: 1)
       )
        }
    }

    private var biasChart: some View {
        Chart(viewModel.biasSummary) { item in
            BarMark(
                x: .value("P&L", item.profit),
                y: .value("Bias", item.label)
            )
            .foregroundStyle(Color.forPnL(item.profit))
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(v.asCompactCurrency)
                    }
                }
            }
        }
        .frame(height: 80)
    }

    private var volChart: some View {
        Chart(viewModel.volRegimeSummary) { item in
            BarMark(
                x: .value("P&L", item.profit),
                y: .value("Regime", item.label)
            )
            .foregroundStyle(Color.forPnL(item.profit))
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(v.asCompactCurrency)
                    }
                }
            }
        }
        .frame(height: 80)
    }
}
