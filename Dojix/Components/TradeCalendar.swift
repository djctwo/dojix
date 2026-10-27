import SwiftUI

/// Calendar view showing daily P&L with color-coded cells
struct TradeCalendar: View {
    let trades: [Trade]

    @State private var selectedMonth: Date = Date()

    private var calendar: Calendar { Calendar.current }

    private var dailyPnL: [Date: Double] {
        var result: [Date: Double] = [:]
        for trade in trades {
            let day = calendar.startOfDay(for: trade.closeTime)
            result[day, default: 0] += trade.profitDouble
        }
        return result
    }

    private var daysInMonth: [Date] {
        guard let range = calendar.range(of: .day, in: .month, for: selectedMonth) else { return [] }
        let components = calendar.dateComponents([.year, .month], from: selectedMonth)
        return range.compactMap { day in
            calendar.date(from: DateComponents(year: components.year, month: components.month, day: day))
        }
    }

    private var firstWeekdayOffset: Int {
        guard let firstDay = daysInMonth.first else { return 0 }
        return (calendar.component(.weekday, from: firstDay) - calendar.firstWeekday + 7) % 7
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("P&L Calendar")
                    .font(.headline)
                Spacer()

                Button {
                    selectedMonth = calendar.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)

                Text(selectedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(width: 140)

                Button {
                    selectedMonth = calendar.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
            }

            // Weekday headers
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(calendar.shortWeekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.smallText)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity)
                }

                // Empty cells for offset
                ForEach(0..<firstWeekdayOffset, id: \.self) { _ in
                    Color.clear
                        .frame(height: 32)
                }

                // Day cells
                ForEach(daysInMonth, id: \.self) { date in
                    dayCell(date: date)
                }
            }

            // Monthly total
            let monthTotal = daysInMonth.reduce(0.0) { $0 + (dailyPnL[$1] ?? 0) }
            let tradeDays = daysInMonth.filter { dailyPnL[$0] != nil }.count
            HStack {
                Text("\(tradeDays) trading days")
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text("Month: \(monthTotal.asCurrency)")
                    .font(.smallText)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.forPnL(monthTotal))
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

    private func dayCell(date: Date) -> some View {
        let pnl = dailyPnL[calendar.startOfDay(for: date)]
        let dayNum = calendar.component(.day, from: date)
        let isToday = calendar.isDateInToday(date)

        return VStack(spacing: 1) {
            Text("\(dayNum)")
                .font(.smallText)
                .fontWeight(isToday ? .bold : .regular)

            if let pnl {
                Text(pnl.asCompactCurrency)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.forPnL(pnl))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 32)
        .background(cellBackground(pnl: pnl, isToday: isToday))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay(
        RoundedRectangle(cornerRadius: 12)
            .stroke(Color.borderCard, lineWidth: 1)
    )
    }

    private func cellBackground(pnl: Double?, isToday: Bool) -> some View {
        Group {
            if let pnl {
                if pnl > 0 {
                    Color.semanticGreen.opacity(0.15)
                } else if pnl < 0 {
                    Color.semanticRed.opacity(0.15)
                } else {
                    Color.clear
                }
            } else if isToday {
                Color.accent.opacity(0.08)
            } else {
                Color.clear
            }
        }
    }
}
