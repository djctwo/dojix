import Foundation
import os

/// ViewModel for the Pulse (live session intelligence) view
@Observable
@MainActor
final class PulseViewModel {
    private nonisolated static let logger = Logger(subsystem: "com.dojix", category: "PulseVM")

    var calendarEvents: [CalendarService.EconomicEvent] = []
    var dangerZones: [CalendarService.DangerZone] = []
    var activeDangerZone: CalendarService.DangerZone?
    var quotes: [TwelveDataService.Quote] = []
    var currencyStrength: [TwelveDataService.CurrencyStrength] = []
    var isLoadingCalendar = false
    var isLoadingQuotes = false

    /// Live data manager for streaming/polling prices
    var liveDataManager = LiveDataManager()
    var calendarError: String?
    var quotesError: String?
    var lastQuoteRefresh: Date?
    var lastCalendarRefresh: Date?

    /// Personalized edge signal based on trade history (legacy, for danger zone scoring)
    var edgeSignal: EdgeSignal?

    /// Per-session edge signals for multi-session display
    var sessionEdgeSignals: [TradingSession: EdgeSignal] = [:]

    /// Per-session metrics for multi-session display
    var sessionMetrics: [TradingSession: MetricsCalculator.PortfolioMetrics] = [:]

    /// Whether the watchlist editor sheet is showing
    var showWatchlistEditor = false

    /// All available forex pairs for the watchlist picker
    static let availablePairs: [String] = [
        "EUR/USD", "GBP/USD", "USD/JPY", "AUD/USD", "USD/CHF", "USD/CAD", "NZD/USD",
        "EUR/GBP", "EUR/JPY", "GBP/JPY", "EUR/CHF", "EUR/AUD", "GBP/AUD",
        "AUD/JPY", "NZD/JPY", "GBP/CHF", "EUR/NZD", "AUD/NZD", "GBP/NZD",
        "CHF/JPY", "CAD/JPY", "AUD/CAD", "EUR/CAD"
    ]

    static let defaultPairs = ["EUR/USD", "GBP/USD", "USD/JPY", "AUD/USD", "GBP/JPY"]

    /// User-customizable watchlist pairs, persisted in UserDefaults
    var watchlistPairs: [String] {
        get { UserDefaults.standard.stringArray(forKey: "watchlist_pairs") ?? Self.defaultPairs }
        set { UserDefaults.standard.set(newValue, forKey: "watchlist_pairs") }
    }

    private var calendarService = CalendarService()

    /// Auto-refresh interval for quotes (2 minutes)
    private static let quoteRefreshInterval: TimeInterval = 120
    /// Auto-refresh interval for calendar (15 minutes)
    private static let calendarRefreshInterval: TimeInterval = 900

    // MARK: - Calendar

    func loadCalendar() async {
        isLoadingCalendar = true
        calendarError = nil

        do {
            let events = try await calendarService.fetchWeekEvents()
            calendarEvents = events
            // Danger zones only from today's high-impact events
            let todayEvents = events.filter { Calendar.current.isDateInToday($0.date) }
            dangerZones = await calendarService.dangerZones(from: todayEvents)
            activeDangerZone = await calendarService.isInDangerZone(events: todayEvents)
            lastCalendarRefresh = Date()
        } catch is CancellationError {
            // Task cancelled by SwiftUI view lifecycle — ignore silently
            isLoadingCalendar = false
            return
        } catch let error as URLError where error.code == .cancelled {
            // URLSession cancelled by SwiftUI task teardown — ignore silently
            isLoadingCalendar = false
            return
        } catch {
            calendarError = error.localizedDescription
            Self.logger.error("Calendar fetch failed: \(error.localizedDescription)")
        }

        isLoadingCalendar = false
    }

    // MARK: - Live Quotes

    /// Quotes to show on screen. When a streaming source is active, its prices are
    /// used (previously streamed prices were received but never displayed); the
    /// day's open from the last REST quote, if any, is kept for the change column.
    var displayQuotes: [TwelveDataService.Quote] {
        let streamed = liveDataManager.latestPrices.values
        guard liveDataManager.activeSource.isStreaming, !streamed.isEmpty else { return quotes }
        let latestByPair = Dictionary(streamed.map { (Self.pairKey($0.symbol), $0) }) { a, b in
            a.timestamp >= b.timestamp ? a : b
        }
        let restByPair = Dictionary(quotes.map { (Self.pairKey($0.symbol), $0) }) { a, _ in a }
        return watchlistPairs.compactMap { pair in
            let key = Self.pairKey(pair)
            guard let price = latestByPair[key] else { return restByPair[key] }
            let open = restByPair[key]?.open ?? price.mid
            let change = price.mid - open
            return TwelveDataService.Quote(
                symbol: pair,
                open: open,
                high: max(open, price.mid, restByPair[key]?.high ?? price.mid),
                low: min(open, price.mid, restByPair[key]?.low ?? price.mid),
                close: price.mid,
                change: change,
                changePercent: open != 0 ? change / open * 100 : 0,
                timestamp: price.timestamp
            )
        }
    }

    /// "EUR/USD", "EUR_USD" and "EURUSD" all name the same pair
    nonisolated static func pairKey(_ symbol: String) -> String {
        symbol.uppercased().filter { $0.isLetter }
    }

    /// Error to show for live prices: REST error, or the streaming source's error
    var liveQuotesError: String? {
        if liveDataManager.activeSource.isStreaming, case .error(let message) = liveDataManager.status {
            return message
        }
        return liveDataManager.activeSource.isStreaming ? nil : quotesError
    }

    /// Start the live data manager (streaming or polling based on user setting)
    func startLiveData() async {
        await liveDataManager.start(symbols: watchlistPairs)

        // If REST polling, also do an initial direct fetch for quote data
        if !liveDataManager.activeSource.isStreaming {
            await loadQuotesREST()
        }
    }

    /// Direct REST fetch for initial load and polling fallback
    func loadQuotesREST() async {
        guard let apiKey = KeychainHelper.twelveDataAPIKey, !apiKey.isEmpty else {
            quotesError = "Add an API key in Settings for live prices"
            return
        }

        isLoadingQuotes = true
        quotesError = nil

        do {
            let service = TwelveDataService(apiKey: apiKey)
            quotes = try await service.getQuotes(symbols: watchlistPairs)
            currencyStrength = await service.calculateStrength(from: quotes)
            lastQuoteRefresh = Date()
        } catch is CancellationError {
            isLoadingQuotes = false
            return
        } catch let error as URLError where error.code == .cancelled {
            isLoadingQuotes = false
            return
        } catch {
            quotesError = error.localizedDescription
            Self.logger.error("Quote fetch failed: \(error.localizedDescription)")
        }

        isLoadingQuotes = false
    }

    // MARK: - Auto-Refresh

    /// Start auto-refresh loop for quotes and calendar
    func startAutoRefresh() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Self.quoteRefreshInterval))
            guard !Task.isCancelled else { break }

            // REST polling: refresh quotes directly
            if !liveDataManager.activeSource.isStreaming {
                await loadQuotesREST()
            }

            // Refresh calendar periodically
            if let lastCal = lastCalendarRefresh,
               Date().timeIntervalSince(lastCal) >= Self.calendarRefreshInterval {
                await loadCalendar()
            }
        }
    }

    // MARK: - Personalized Edge Signals

    /// Generate edge signals for all currently active sessions
    func generateEdgeSignals(trades: [Trade]) {
        let activeSessions = Date().activeTradingSessions
        let currentHour = Date().utcHour

        guard trades.count >= Configuration.minimumTradesForAnalysis else {
            let insufficientSignal = EdgeSignal(
                level: .neutral,
                message: "Need more trades to generate signals",
                details: "Import at least \(Configuration.minimumTradesForAnalysis) trades for personalized signals."
            )
            edgeSignal = insufficientSignal
            for session in activeSessions {
                sessionEdgeSignals[session] = insufficientSignal
            }
            return
        }

        for session in activeSessions {
            // Include overlap-tagged trades in both London and NY analysis
            let relevantTrades = trades.filter { session.relatedSessions.contains($0.session) }
            let hourTrades = relevantTrades.filter { $0.hour == currentHour }

            let metrics = MetricsCalculator.calculate(from: relevantTrades)
            let hourMetrics = MetricsCalculator.calculate(from: hourTrades)

            sessionMetrics[session] = metrics

            var score = 0.0
            var factors: [String] = []

            // Session performance
            if metrics.totalTrades >= 5 {
                if metrics.winRate >= 60 && metrics.profitFactor >= 1.5 {
                    score += 2
                    factors.append("\(String(format: "%.0f", metrics.winRate))% win rate, \(String(format: "%.1f", metrics.profitFactor)) PF")
                } else if metrics.winRate < 40 || metrics.profitFactor < 0.8 {
                    score -= 2
                    factors.append("Historically unprofitable (\(String(format: "%.0f", metrics.winRate))% WR)")
                }
            }

            // Hour performance within this session
            if hourMetrics.totalTrades >= 3 {
                if hourMetrics.winRate >= 60 && hourMetrics.totalProfit > 0 {
                    score += 1
                    factors.append("\(currentHour):00 UTC is a strong hour")
                } else if hourMetrics.totalProfit < 0 {
                    score -= 1
                    factors.append("\(currentHour):00 UTC has negative P&L")
                }
            }

            // Danger zone penalty
            if activeDangerZone != nil {
                score -= 2
                factors.append("High-impact news active")
            }

            let level: EdgeSignal.Level
            let message: String
            if score >= 2 {
                level = .strong
                message = "Conditions match your edge"
            } else if score >= 0 {
                level = .neutral
                message = "Average conditions"
            } else {
                level = .avoid
                message = "Poor conditions — sit out"
            }

            sessionEdgeSignals[session] = EdgeSignal(
                level: level,
                message: message,
                details: factors.isEmpty ? "Insufficient data for this session." : factors.joined(separator: ". ") + "."
            )
        }

        // Set primary edge signal to the best active session's signal
        edgeSignal = activeSessions
            .compactMap { sessionEdgeSignals[$0] }
            .sorted { $0.level.score > $1.level.score }
            .first
    }

    // MARK: - Computed

    var highImpactEvents: [CalendarService.EconomicEvent] {
        calendarEvents.filter { $0.impact == .high }
    }

    var upcomingEvents: [CalendarService.EconomicEvent] {
        calendarEvents.filter { $0.date > Date() }
    }

    var lastRefreshText: String? {
        guard let date = lastQuoteRefresh else { return nil }
        let seconds = Int(saturating: Date().timeIntervalSince(date))
        if seconds < 60 { return "Updated just now" }
        return "Updated \(seconds / 60)m ago"
    }

    // MARK: - Historical Event Performance

    /// Stored trades for event history lookup
    private(set) var trades: [Trade] = []

    /// Store trades for historical event analysis (called from PulseView .task)
    func setTrades(_ trades: [Trade]) {
        self.trades = trades
    }

    /// Historical performance for a calendar event type (matched by title keywords)
    func eventHistory(for event: CalendarService.EconomicEvent) -> EventHistoryResult? {
        guard trades.count >= 20 else { return nil }

        let category = categorizeEvent(event)
        guard let category else { return nil }

        let matching = trades.filter { matchesEventCategory($0, category: category) }
        guard matching.count >= 3 else { return nil }

        let wins = matching.filter(\.isWin).count
        let losses = matching.count - wins
        let avgPnL = matching.map(\.profitDouble).reduce(0, +) / Double(matching.count)
        return EventHistoryResult(wins: wins, losses: losses, avgPnL: avgPnL, total: matching.count)
    }

    struct EventHistoryResult {
        let wins: Int
        let losses: Int
        let avgPnL: Double
        let total: Int
    }

    private enum EventCategory { case nfp, fomc, cpi, ecb, boe }

    private func categorizeEvent(_ event: CalendarService.EconomicEvent) -> EventCategory? {
        let title = event.title.lowercased()
        if title.contains("non-farm") || title.contains("nonfarm") || title.contains("nfp") { return .nfp }
        if title.contains("fomc") || title.contains("federal funds") { return .fomc }
        if title.contains("cpi") || title.contains("consumer price") { return .cpi }
        if (title.contains("ecb") || (event.country == "EUR" && title.contains("rate"))) { return .ecb }
        if (title.contains("boe") || title.contains("bank of england") || (event.country == "GBP" && title.contains("rate"))) { return .boe }
        return nil
    }

    private func matchesEventCategory(_ trade: Trade, category: EventCategory) -> Bool {
        let cal = Calendar.current
        let c = cal.dateComponents([.weekday, .weekOfMonth, .day, .month, .hour], from: trade.openTime)
        let wd = c.weekday ?? 0, wom = c.weekOfMonth ?? 0
        let day = c.day ?? 0, month = c.month ?? 0, hour = c.hour ?? 0

        switch category {
        case .nfp: return wd == 6 && wom == 1
        case .fomc: return wd == 4 && [1, 3, 5, 6, 7, 9, 11, 12].contains(month) && (15...28).contains(day)
        case .cpi: return (wd == 3 || wd == 4) && (10...14).contains(day)
        case .ecb: return wd == 5 && [1, 3, 4, 6, 7, 9, 10, 12].contains(month) && (7...21).contains(day) && (11...15).contains(hour)
        case .boe: return wd == 5 && [2, 3, 5, 6, 8, 9, 11, 12].contains(month) && (1...14).contains(day) && (10...14).contains(hour)
        }
    }
}

// MARK: - Edge Signal

struct EdgeSignal {
    enum Level: Comparable {
        case avoid, neutral, strong

        /// Numeric score for sorting (higher = better)
        var score: Int {
            switch self {
            case .avoid: 0
            case .neutral: 1
            case .strong: 2
            }
        }
    }

    let level: Level
    let message: String
    let details: String
}
