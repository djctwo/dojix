import SwiftUI

/// Shows P&L correlation between traded pairs to identify diversification
struct PairCorrelation: View {
    let trades: [Trade]

    private struct PairPnL {
        let symbol: String
        var dailyPnL: [String: Double] = [:] // date string -> P&L
    }

    /// Cached formatter — DateFormatter init is expensive, reuse across computed properties
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var pairs: [String] {
        Array(Set(trades.map(\.symbol))).sorted()
    }

    /// Cached daily P&L series per pair — shared by correlationMatrix and dataQualitySummary
    private var pairDailyPnL: (data: [String: [String: Double]], allDates: Set<String>) {
        var result: [String: [String: Double]] = [:]
        for pair in pairs { result[pair] = [:] }
        for trade in trades {
            let dateKey = Self.dayFormatter.string(from: trade.closeTime)
            result[trade.symbol, default: [:]][dateKey, default: 0] += trade.profitDouble
        }

        return (result, Set(result.values.flatMap(\.keys)))
    }

    private var correlationMatrix: [[Double]] {
        guard pairs.count >= 2 else { return [] }
        let (pairData, allDates) = pairDailyPnL

        var matrix: [[Double]] = Array(repeating: Array(repeating: 0, count: pairs.count), count: pairs.count)
        for i in 0..<pairs.count {
            for j in 0..<pairs.count {
                if i == j {
                    matrix[i][j] = 1.0
                } else if j > i {
                    let (corr, _) = pearsonCorrelation(
                        series1: pairData[pairs[i]] ?? [:],
                        series2: pairData[pairs[j]] ?? [:],
                        dates: allDates
                    )
                    matrix[i][j] = corr
                    matrix[j][i] = corr
                }
            }
        }
        return matrix
    }

    /// Returns (correlation, overlapping day count)
    private func pearsonCorrelation(series1: [String: Double], series2: [String: Double], dates: Set<String>) -> (Double, Int) {
        let commonDates = dates.filter { series1[$0] != nil && series2[$0] != nil }
        guard commonDates.count >= 2 else { return (0, commonDates.count) }

        let x = commonDates.compactMap { series1[$0] }
        let y = commonDates.compactMap { series2[$0] }
        guard x.count == y.count, x.count == commonDates.count else { return (0, commonDates.count) }
        let n = Double(x.count)

        let meanX = x.reduce(0, +) / n
        let meanY = y.reduce(0, +) / n

        var sumXY = 0.0, sumX2 = 0.0, sumY2 = 0.0
        for i in 0..<x.count {
            let dx = x[i] - meanX
            let dy = y[i] - meanY
            sumXY += dx * dy
            sumX2 += dx * dx
            sumY2 += dy * dy
        }

        let denominator = sqrt(sumX2 * sumY2)
        guard denominator > 0 else { return (0, commonDates.count) }
        return (sumXY / denominator, commonDates.count)
    }

    /// Counts how many pair combinations have >= 2 overlapping trading days
    private var dataQualitySummary: (sufficient: Int, total: Int, maxOverlap: Int) {
        guard pairs.count >= 2 else { return (0, 0, 0) }
        let (pairData, allDates) = pairDailyPnL

        var sufficient = 0
        var total = 0
        var maxOverlap = 0

        for i in 0..<pairs.count {
            for j in (i + 1)..<pairs.count {
                total += 1
                let (_, overlap) = pearsonCorrelation(
                    series1: pairData[pairs[i]] ?? [:],
                    series2: pairData[pairs[j]] ?? [:],
                    dates: allDates
                )
                maxOverlap = max(maxOverlap, overlap)
                if overlap >= 2 { sufficient += 1 }
            }
        }

        return (sufficient, total, maxOverlap)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Pair Correlation", systemImage: "chart.dots.scatter")
                .font(.headline)

            if pairs.count < 2 {
                Text("Need trades in at least 2 pairs")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                let matrix = correlationMatrix
                let quality = dataQualitySummary

                // Insufficient data warning
                if quality.sufficient == 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(Color.accent)
                        Text("Not enough overlapping trading days between pairs to calculate meaningful correlations. Trade the same pairs on the same days to populate this chart.")
                            .font(.smallText)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(10)
                    .background(Color.accent.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if quality.sufficient < quality.total {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(Color.accent)
                        Text("\(quality.sufficient)/\(quality.total) pair combinations have enough overlapping days (max \(quality.maxOverlap) days)")
                            .font(.smallText)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                // Header row
                HStack(spacing: 2) {
                    Text("")
                        .frame(width: 65)
                    ForEach(pairs, id: \.self) { pair in
                        Text(String(pair.prefix(6)))
                            .font(.monoSmall)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: 54)
                            .rotationEffect(.degrees(-45))
                    }
                }
                .frame(height: 36)

                // Matrix rows
                ForEach(Array(pairs.enumerated()), id: \.element) { i, pair in
                    HStack(spacing: 2) {
                        Text(String(pair.prefix(6)))
                            .font(.monoSmall)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: 65, alignment: .trailing)
                            .padding(.trailing, 4)

                        ForEach(0..<pairs.count, id: \.self) { j in
                            if !matrix.isEmpty && i < matrix.count && j < matrix[i].count {
                                correlationCell(matrix[i][j], isDiagonal: i == j)
                            }
                        }
                    }
                }

                // Legend
                HStack(spacing: 8) {
                    legendItem(color: Color.semanticRed, label: "High (+)")
                    legendItem(color: Color.semanticRed.opacity(0.3), label: "Moderate (+)")
                    legendItem(color: Color.textTertiary.opacity(0.15), label: "Low")
                    legendItem(color: Color.semanticGreen.opacity(0.3), label: "Moderate (-)")
                    legendItem(color: Color.semanticGreen, label: "High (-)")
                }
                .font(.system(size: 10))
                .padding(.top, 4)

                // Insight
                if let insight = diversificationInsight(matrix) {
                    HStack(spacing: 4) {
                        Image(systemName: insight.icon)
                            .font(.caption)
                            .foregroundStyle(insight.color)
                        Text(insight.text)
                            .font(.smallText)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
        .padding(16)
    }

    private func correlationCell(_ value: Double, isDiagonal: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(isDiagonal ? Color.accent.opacity(0.5) : correlationColor(value))
            if !isDiagonal {
                Text(String(format: "%.2f", value))
                    .font(.monoSmall)
                    .foregroundStyle(abs(value) > 0.4 ? Color.textPrimary : Color.textSecondary)
            } else {
                Text("1.00")
                    .font(.monoSmall)
                    .foregroundStyle(Color.accent)
            }
        }
        .frame(width: 54, height: 32)
    }

    private func correlationColor(_ value: Double) -> Color {
        let absVal = min(abs(value), 1.0)
        let baseOpacity = 0.15

        if value > 0 {
            // Positive correlation (concentrated risk) — red tones
            return Color.semanticRed.opacity(baseOpacity + absVal * (0.8 - baseOpacity))
        } else if value < 0 {
            // Negative correlation (diversified) — green tones
            return Color.semanticGreen.opacity(baseOpacity + absVal * (0.8 - baseOpacity))
        } else {
            // Zero — visible warm neutral
            return Color.textTertiary.opacity(0.15)
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private struct Insight {
        let icon: String
        let color: Color
        let text: String
    }

    private func diversificationInsight(_ matrix: [[Double]]) -> Insight? {
        guard !matrix.isEmpty, pairs.count >= 2 else { return nil }

        // Average off-diagonal correlation
        var totalCorr = 0.0
        var count = 0
        for i in 0..<matrix.count {
            for j in (i + 1)..<matrix[i].count {
                totalCorr += matrix[i][j]
                count += 1
            }
        }
        guard count > 0 else { return nil }
        let avgCorr = totalCorr / Double(count)

        if avgCorr > 0.6 {
            return Insight(
                icon: "exclamationmark.triangle",
                color: .orange,
                text: "High positive correlation (avg \(String(format: "%.2f", avgCorr))) — concentrated risk across pairs"
            )
        } else if avgCorr < -0.3 {
            return Insight(
                icon: "checkmark.circle",
                color: Color.semanticGreen,
                text: "Good diversification (avg \(String(format: "%.2f", avgCorr))) — pairs offset each other's risk"
            )
        } else {
            return Insight(
                icon: "info.circle",
                color: Color.accent,
                text: "Moderate correlation (avg \(String(format: "%.2f", avgCorr))) — reasonably diversified portfolio"
            )
        }
    }
}
