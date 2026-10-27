import Foundation
import os

/// Live forex market data from Twelve Data API (800 requests/day free tier)
actor TwelveDataService {
    private static let logger = Logger(subsystem: "com.dojix", category: "TwelveData")

    private let baseURL = "https://api.twelvedata.com"
    private let session: URLSession
    private let apiKey: String

    /// Rate limiting: track daily requests
    private var requestCount: Int = 0
    private var lastResetDate: Date = Date()
    private let dailyLimit = 800

    init(apiKey: String) {
        self.apiKey = apiKey
        self.session = SecureSession.make(timeout: 15)
    }

    // MARK: - Price Data

    /// Current price quote for a forex pair
    struct Quote: Sendable {
        let symbol: String
        let open: Double
        let high: Double
        let low: Double
        let close: Double
        let change: Double
        let changePercent: Double
        let timestamp: Date
    }

    /// Get real-time quote for a forex pair (e.g., "EUR/USD")
    func getQuote(symbol: String) async throws -> Quote {
        try checkRateLimit()

        guard var components = URLComponents(string: "\(baseURL)/quote") else {
            throw TwelveDataError.invalidData
        }
        components.queryItems = [
            URLQueryItem(name: "symbol", value: symbol),
            URLQueryItem(name: "apikey", value: apiKey)
        ]
        guard let url = components.url else { throw TwelveDataError.invalidData }
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TwelveDataError.invalidData
        }
        incrementRequestCount()

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TwelveDataError.invalidData
        }

        // Check for API error responses
        if let status = json["status"] as? String, status == "error" {
            let message = json["message"] as? String ?? "Unknown error"
            Self.logger.error("Twelve Data API error: \(message)")
            throw TwelveDataError.invalidData
        }

        return try parseQuote(json, symbol: symbol)
    }

    /// Get quotes for multiple forex pairs in one request
    func getQuotes(symbols: [String]) async throws -> [Quote] {
        try checkRateLimit()

        let symbolList = symbols.joined(separator: ",")
        guard var components = URLComponents(string: "\(baseURL)/quote") else {
            throw TwelveDataError.invalidData
        }
        components.queryItems = [
            URLQueryItem(name: "symbol", value: symbolList),
            URLQueryItem(name: "apikey", value: apiKey)
        ]
        guard let url = components.url else { throw TwelveDataError.invalidData }
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TwelveDataError.invalidData
        }
        incrementRequestCount()

        // Multi-symbol response is a dict keyed by symbol
        if symbols.count == 1 {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw TwelveDataError.invalidData
            }
            if let status = json["status"] as? String, status == "error" {
                let message = json["message"] as? String ?? "Unknown error"
                Self.logger.error("Twelve Data API error: \(message)")
                throw TwelveDataError.invalidData
            }
            return [try parseQuote(json, symbol: symbols[0])]
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else {
            throw TwelveDataError.invalidData
        }
        return symbols.compactMap { symbol in
            guard let entry = json[symbol] else { return nil }
            do {
                return try parseQuote(entry, symbol: symbol)
            } catch {
                Self.logger.warning("Failed to parse quote for \(symbol)")
                return nil
            }
        }
    }

    private func parseQuote(_ json: [String: Any], symbol: String) throws -> Quote {
        guard let close = Double(json["close"] as? String ?? "") else {
            throw TwelveDataError.invalidData
        }

        return Quote(
            symbol: symbol,
            open: Double(json["open"] as? String ?? "") ?? 0,
            high: Double(json["high"] as? String ?? "") ?? 0,
            low: Double(json["low"] as? String ?? "") ?? 0,
            close: close,
            change: Double(json["change"] as? String ?? "") ?? 0,
            changePercent: Double(json["percent_change"] as? String ?? "") ?? 0,
            timestamp: Date()
        )
    }

    // MARK: - Pair Strength

    /// Currency pair strength based on daily change across majors
    struct CurrencyStrength: Sendable {
        let currency: String
        let strength: Double  // Normalized -1 to 1
    }

    /// Calculate currency strength from major pair quotes
    func calculateStrength(from quotes: [Quote]) -> [CurrencyStrength] {
        var scores: [String: Double] = [:]

        for quote in quotes {
            let parts = quote.symbol.split(separator: "/")
            guard parts.count == 2 else { continue }
            let base = String(parts[0])
            let counter = String(parts[1])

            scores[base, default: 0] += quote.changePercent
            scores[counter, default: 0] -= quote.changePercent
        }

        let maxAbs = scores.values.map { abs($0) }.max() ?? 1
        guard maxAbs > 0 else { return [] }

        return scores.map { currency, score in
            CurrencyStrength(currency: currency, strength: score / maxAbs)
        }
        .sorted { abs($0.strength) > abs($1.strength) }
    }

    // MARK: - Rate Limiting

    private func checkRateLimit() throws {
        resetCounterIfNewDay()
        if requestCount >= dailyLimit {
            Self.logger.warning("Daily rate limit reached (\(self.dailyLimit) requests)")
            throw TwelveDataError.rateLimitExceeded
        }
    }

    private func incrementRequestCount() {
        resetCounterIfNewDay()
        requestCount += 1
        Self.logger.debug("API request \(self.requestCount)/\(self.dailyLimit)")
    }

    private func resetCounterIfNewDay() {
        let calendar = Calendar.current
        if !calendar.isDate(lastResetDate, inSameDayAs: Date()) {
            requestCount = 0
            lastResetDate = Date()
        }
    }

    var remainingRequests: Int {
        resetCounterIfNewDay()
        return max(0, dailyLimit - requestCount)
    }

    // MARK: - Errors

    enum TwelveDataError: LocalizedError {
        case invalidData
        case rateLimitExceeded
        case noAPIKey

        var errorDescription: String? {
            switch self {
            case .invalidData: "Invalid data from Twelve Data API"
            case .rateLimitExceeded: "Daily API limit reached (800 requests). Resets at midnight."
            case .noAPIKey: "No Twelve Data API key configured. Add it in Settings."
            }
        }
    }
}
