import Foundation
import os

/// Economic calendar events from free API sources
actor CalendarService {
    private static let logger = Logger(subsystem: "com.dojix", category: "Calendar")

    private let session: URLSession

    init() {
        self.session = SecureSession.make(timeout: 15)
    }

    // MARK: - Models

    /// Impact level for economic events
    enum Impact: String, Sendable, Comparable {
        case low = "Low"
        case medium = "Medium"
        case high = "High"

        static func < (lhs: Impact, rhs: Impact) -> Bool {
            let order: [Impact] = [.low, .medium, .high]
            return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
        }
    }

    /// An economic calendar event
    struct EconomicEvent: Identifiable, Sendable {
        let id = UUID()
        let title: String
        let country: String
        let date: Date
        let impact: Impact
        let actual: String?
        let forecast: String?
        let previous: String?
    }

    /// Danger zone: high-impact event windows where trading is risky
    struct DangerZone: Identifiable, Sendable {
        let id = UUID()
        let event: EconomicEvent
        let avoidStart: Date  // 15 min before
        let avoidEnd: Date    // 15 min after
        let affectedPairs: [String]
    }

    // MARK: - Fetch Events

    private static let calendarURL = "https://nfs.faireconomy.media/ff_calendar_thisweek.json"

    /// Fetch today's economic events (uses Forex Factory scrape fallback)
    func fetchTodayEvents() async throws -> [EconomicEvent] {
        guard let url = URL(string: Self.calendarURL) else {
            throw CalendarError.networkError
        }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw CalendarError.networkError
        }

        guard let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
              contentType.contains("json") else {
            throw CalendarError.invalidData
        }

        guard let events = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw CalendarError.invalidData
        }

        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!

        return events.compactMap { parseEvent($0) }
            .filter { $0.date >= today && $0.date < tomorrow }
            .sorted { $0.date < $1.date }
    }

    /// Fetch this week's economic events
    func fetchWeekEvents() async throws -> [EconomicEvent] {
        guard let url = URL(string: Self.calendarURL) else {
            throw CalendarError.networkError
        }
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw CalendarError.networkError
        }

        guard let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
              contentType.contains("json") else {
            throw CalendarError.invalidData
        }

        guard let events = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw CalendarError.invalidData
        }

        return events.compactMap { parseEvent($0) }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Danger Zones

    /// Compute danger zones from high-impact events
    func dangerZones(from events: [EconomicEvent]) -> [DangerZone] {
        events
            .filter { $0.impact == .high }
            .map { event in
                DangerZone(
                    event: event,
                    avoidStart: event.date.addingTimeInterval(-15 * 60),
                    avoidEnd: event.date.addingTimeInterval(15 * 60),
                    affectedPairs: pairsAffectedBy(country: event.country)
                )
            }
    }

    /// Check if current time falls in any danger zone
    func isInDangerZone(events: [EconomicEvent]) -> DangerZone? {
        let now = Date()
        return dangerZones(from: events).first { zone in
            now >= zone.avoidStart && now <= zone.avoidEnd
        }
    }

    // MARK: - Helpers

    private func parseEvent(_ json: [String: Any]) -> EconomicEvent? {
        guard let title = json["title"] as? String,
              let country = json["country"] as? String,
              let dateStr = json["date"] as? String else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: dateStr)
            ?? ISO8601DateFormatter().date(from: dateStr)
            ?? Date()

        let impactStr = json["impact"] as? String ?? "Low"
        let impact: Impact
        switch impactStr.lowercased() {
        case "high": impact = .high
        case "medium": impact = .medium
        default: impact = .low
        }

        return EconomicEvent(
            title: title,
            country: country,
            date: date,
            impact: impact,
            actual: json["actual"] as? String,
            forecast: json["forecast"] as? String,
            previous: json["previous"] as? String
        )
    }

    /// Map country codes to affected forex pairs
    private func pairsAffectedBy(country: String) -> [String] {
        switch country.uppercased() {
        case "USD": ["EURUSD", "GBPUSD", "USDJPY", "AUDUSD"]
        case "EUR": ["EURUSD", "EURGBP", "EURJPY"]
        case "GBP": ["GBPUSD", "GBPJPY", "EURGBP"]
        case "JPY": ["USDJPY", "GBPJPY", "EURJPY"]
        case "AUD": ["AUDUSD", "AUDJPY"]
        case "CAD": ["USDCAD"]
        case "CHF": ["USDCHF"]
        case "NZD": ["NZDUSD"]
        default: []
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    // MARK: - Errors

    enum CalendarError: LocalizedError {
        case invalidData
        case networkError

        var errorDescription: String? {
            switch self {
            case .invalidData: "Invalid calendar data"
            case .networkError: "Failed to fetch economic calendar"
            }
        }
    }
}
