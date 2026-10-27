import Foundation
import GRDB
import os

/// ViewModel for the Journal (trade list) view
@Observable
@MainActor
final class JournalViewModel {
    private let repository: TradeRepository
    private let database: DatabaseManager
    private nonisolated static let logger = Logger(subsystem: "com.dojix", category: "JournalVM")

    var trades: [Trade] = []
    var isLoading = false
    var searchText = ""
    var selectedSymbolFilter: String?
    var selectedSessionFilter: TradingSession?
    var selectedDirectionFilter: TradeDirection?
    var selectedDateRange: DateRange = .all

    enum DateRange: String, CaseIterable {
        case all = "All Time"
        case today = "Today"
        case thisWeek = "This Week"
        case thisMonth = "This Month"
        case last30 = "Last 30 Days"
        case last90 = "Last 90 Days"
    }

    private var observation: AnyDatabaseCancellable?

    init(repository: TradeRepository, database: DatabaseManager) {
        self.repository = repository
        self.database = database
        startObserving()
    }

    // MARK: - Observation

    private func startObserving() {
        self.observation = repository.observeAll(
            onError: { error in
                Self.logger.error("Observation error: \(error.localizedDescription)")
            },
            onChange: { [weak self] trades in
                Task { @MainActor in
                    self?.trades = trades
                }
            }
        )
    }

    // MARK: - Filtered Trades (sorting handled by Table in View)

    var filteredTrades: [Trade] {
        var result = trades

        if let symbol = selectedSymbolFilter {
            result = result.filter { $0.symbol == symbol }
        }
        if let session = selectedSessionFilter {
            result = result.filter { $0.session == session }
        }
        if let direction = selectedDirectionFilter {
            result = result.filter { $0.direction == direction }
        }
        if selectedDateRange != .all {
            let cutoff = dateRangeCutoff
            result = result.filter { $0.closeTime >= cutoff }
        }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.symbol.lowercased().contains(query) ||
                $0.comment.lowercased().contains(query) ||
                $0.dayOfWeek.lowercased().contains(query)
            }
        }

        return result
    }

    var uniqueSymbols: [String] {
        Array(Set(trades.map(\.symbol))).sorted()
    }

    var tradeCount: Int { filteredTrades.count }

    var totalFilteredProfit: Double {
        filteredTrades.reduce(0) { $0 + $1.profitDouble }
    }

    private var dateRangeCutoff: Date {
        let calendar = Calendar.current
        let now = Date()
        switch selectedDateRange {
        case .all: return .distantPast
        case .today: return calendar.startOfDay(for: now)
        case .thisWeek: return calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
        case .thisMonth: return calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        case .last30: return calendar.date(byAdding: .day, value: -30, to: now) ?? now
        case .last90: return calendar.date(byAdding: .day, value: -90, to: now) ?? now
        }
    }
}
