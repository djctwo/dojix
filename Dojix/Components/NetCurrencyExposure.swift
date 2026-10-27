import SwiftUI

/// Horizontal bar chart showing net lot exposure per currency across all traded pairs.
/// "Think in currencies, not pairs."
struct NetCurrencyExposure: View {
    let trades: [Trade]

    // MARK: - Data Model

    private struct CurrencyExposure: Identifiable {
        let currency: String
        let netLots: Double
        var id: String { currency }
    }

    private struct CorrelatedInsight: Identifiable {
        let currency: String
        let direction: String
        let pairs: [String]
        var id: String { "\(currency)-\(direction)" }
    }

    // MARK: - Computed Properties

    private var exposures: [CurrencyExposure] {
        var map: [String: Double] = [:]
        for trade in trades {
            let sign: Double = trade.direction == .buy ? 1 : -1
            map[trade.baseCurrency, default: 0] += sign * trade.lots
            map[trade.quoteCurrency, default: 0] -= sign * trade.lots
        }
        return map.map { CurrencyExposure(currency: $0.key, netLots: $0.value) }
            .sorted { abs($0.netLots) > abs($1.netLots) }
    }

    private var maxAbsExposure: Double {
        exposures.map { abs($0.netLots) }.max() ?? 1
    }

    private var totalAbsExposure: Double {
        max(exposures.map { abs($0.netLots) }.reduce(0, +), 1)
    }

    private var concentration: (currency: String, percent: Double) {
        guard let top = exposures.first else { return ("--", 0) }
        return (top.currency, abs(top.netLots) / totalAbsExposure * 100)
    }

    private var concentrationColor: Color {
        if concentration.percent > 70 { return .semanticRed }
        if concentration.percent > 50 { return .orange }
        return .secondary
    }

    private var correlatedInsights: [CorrelatedInsight] {
        var currencyPairs: [String: [(pair: String, dir: String)]] = [:]
        for trade in trades {
            let baseDir = trade.direction == .buy ? "long" : "short"
            let quoteDir = trade.direction == .buy ? "short" : "long"
            currencyPairs[trade.baseCurrency, default: []].append((trade.symbol, baseDir))
            currencyPairs[trade.quoteCurrency, default: []].append((trade.symbol, quoteDir))
        }
        var results: [CorrelatedInsight] = []
        for (currency, entries) in currencyPairs {
            guard Set(entries.map(\.pair)).count >= 2 else { continue }
            for dir in ["long", "short"] {
                let pairs = Set(entries.filter { $0.dir == dir }.map(\.pair))
                guard pairs.count >= 2 else { continue }
                results.append(CorrelatedInsight(currency: currency, direction: dir, pairs: pairs.sorted()))
            }
        }
        return results.sorted { abs(lotsFor($0.currency)) > abs(lotsFor($1.currency)) }
    }

    private func lotsFor(_ currency: String) -> Double {
        exposures.first { $0.currency == currency }?.netLots ?? 0
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Net Currency Exposure", systemImage: "scalemass")
                    .font(.headline)
                Spacer()
                ConfidenceBadge(sampleSize: trades.count, compact: true)
            }

            if trades.count < 5 {
                Text("Need at least 5 trades")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                barChart
                concentrationRow
                correlatedPairInsights
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

    // MARK: - Subviews

    private var barChart: some View {
        VStack(spacing: 6) {
            ForEach(exposures) { exposure in
                HStack(spacing: 8) {
                    Text(exposure.currency)
                        .font(.monoSubtitle)
                        .fontWeight(.bold)
                        .frame(width: 32, alignment: .trailing)
                    exposureBar(exposure)
                    Text(String(format: "%+.2f", exposure.netLots))
                        .font(.monoSubtitle)
                        .foregroundStyle(exposure.netLots >= 0 ? Color.semanticGreen : Color.semanticRed)
                        .frame(width: 50, alignment: .trailing)
                }
            }
        }
    }

    private func exposureBar(_ exposure: CurrencyExposure) -> some View {
        GeometryReader { geo in
            let midX = geo.size.width / 2
            let barWidth = abs(exposure.netLots / maxAbsExposure) * midX
            let color: Color = exposure.netLots >= 0 ? .semanticGreen : .semanticRed
            let offset = exposure.netLots >= 0 ? midX : midX - barWidth

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 1)
                    .offset(x: midX)
                RoundedRectangle(cornerRadius: 2)
                    .fill(color.opacity(0.8))
                    .frame(width: max(barWidth, 2), height: 14)
                    .offset(x: offset)
            }
        }
        .frame(height: 16)
    }

    private var concentrationRow: some View {
        HStack(spacing: 4) {
            if concentration.percent > 50 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(concentrationColor)
                    .font(.smallText)
            }
            Text("\(String(format: "%.0f", concentration.percent))% of your volume is \(concentration.currency)-denominated")
                .font(.smallText)
                .foregroundStyle(concentrationColor)
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private var correlatedPairInsights: some View {
        if !correlatedInsights.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(correlatedInsights.prefix(3)) { insight in
                    let pairs = insight.pairs.map { "\(String($0.prefix(3)))/\(String($0.suffix(3)))" }
                    Text("\(insight.pairs.count)x \(insight.direction) \(insight.currency) via \(pairs.joined(separator: " + "))")
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
    }
}
