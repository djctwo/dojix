import SwiftUI
import Charts

/// Bar chart showing P&L by hour of day — instantly shows best/worst trading times
struct HourlyPnLChart: View {
    let trades: [Trade]

    private var hourlyData: [(hour: Int, pnl: Double, count: Int)] {
        let grouped = Dictionary(grouping: trades) { $0.hour }
        return (0..<24).map { hour in
            let hourTrades = grouped[hour] ?? []
            let pnl = hourTrades.reduce(0.0) { $0 + $1.profitDouble }
            return (hour: hour, pnl: pnl, count: hourTrades.count)
        }
        .filter { $0.count > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("P&L by Hour (UTC)")
                    .font(.headline)
                ConfidenceBadge(sampleSize: trades.count)
                Spacer()

                if let best = hourlyData.max(by: { $0.pnl < $1.pnl }) {
                    Text("Best: \(best.hour):00 (\(best.pnl.asCompactCurrency))")
                        .font(.smallText)
                        .foregroundStyle(Color.semanticGreen)
                }
            }

            Chart(hourlyData, id: \.hour) { item in
                BarMark(
                    x: .value("Hour", "\(item.hour):00"),
                    y: .value("P&L", item.pnl)
                )
                .foregroundStyle(Color.forPnL(item.pnl))
                .annotation(position: item.pnl >= 0 ? .top : .bottom) {
                    if abs(item.pnl) > 10 {
                        Text("\(item.count)")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textTertiary)
                    }
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
            .frame(height: 180)

            // Session overlay labels
            HStack(spacing: 0) {
                sessionRange("Asian", start: 0, end: 9, color: .asianSession)
                sessionRange("London", start: 7, end: 16, color: .londonSession)
                sessionRange("NY", start: 12, end: 21, color: .nySession)
            }
            .font(.system(size: 11))
        }
        .padding(16)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay(
        RoundedRectangle(cornerRadius: 12)
            .stroke(Color.borderCard, lineWidth: 1)
    )
    }

    private func sessionRange(_ name: String, start: Int, end: Int, color: Color) -> some View {
        HStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: 4, height: 4)
            Text("\(name) \(start)-\(end)")
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.trailing, 8)
    }
}
