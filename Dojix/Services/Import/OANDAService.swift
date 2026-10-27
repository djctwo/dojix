import Foundation
import os

/// Fetches trade history from OANDA REST v20 API
struct OANDAService: Sendable {
    private static let logger = Logger(subsystem: "com.dojix", category: "OANDA")
    private static let practiceBaseURL = "https://api-fxpractice.oanda.com"
    private static let liveBaseURL = "https://api-fxtrade.oanda.com"

    let apiToken: String
    let accountID: String
    let isLive: Bool
    /// Shared pinned session — avoids creating a new URLSession per struct instance
    private static let session = SecureSession.make(timeout: 30)

    private var baseURL: String {
        isLive ? Self.liveBaseURL : Self.practiceBaseURL
    }

    // MARK: - Fetch Trade History

    /// Fetch closed trades from OANDA
    func fetchTrades(from startDate: Date? = nil, to endDate: Date? = nil) async throws -> [Trade] {
        let transactions = try await fetchTransactions(from: startDate, to: endDate)
        return mapTransactionsToTrades(transactions)
    }

    /// Fetch account summary (for validation)
    func fetchAccountSummary() async throws -> AccountSummary {
        let url = "\(baseURL)/v3/accounts/\(accountID)/summary"
        let data = try await makeRequest(url: url)
        let response = try JSONDecoder().decode(AccountSummaryResponse.self, from: data)
        return response.account
    }

    // MARK: - API Requests

    private func fetchTransactions(from startDate: Date?, to endDate: Date?) async throws -> [OANDATransaction] {
        var components = URLComponents(string: "\(baseURL)/v3/accounts/\(accountID)/transactions")
        guard components != nil else { throw OANDAError.invalidURL }

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "type", value: "ORDER_FILL")
        ]

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        if let start = startDate {
            queryItems.append(URLQueryItem(name: "from", value: isoFormatter.string(from: start)))
        } else {
            // Default to last 90 days
            let ninetyDaysAgo = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
            queryItems.append(URLQueryItem(name: "from", value: isoFormatter.string(from: ninetyDaysAgo)))
        }

        if let end = endDate {
            queryItems.append(URLQueryItem(name: "to", value: isoFormatter.string(from: end)))
        }

        components?.queryItems = queryItems

        guard let url = components?.url?.absoluteString else {
            throw OANDAError.invalidURL
        }

        // OANDA paginates — first get transaction IDs, then fetch pages
        let data = try await makeRequest(url: url)

        // Parse the transaction ID range
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let pageURLs = json?["pages"] as? [String] else {
            throw OANDAError.invalidResponse
        }

        // Fetch each page (validate domain to prevent SSRF via attacker-controlled pagination URLs)
        var allTransactions: [OANDATransaction] = []
        for pageURL in pageURLs {
            guard Self.isTrustedOANDAURL(pageURL) else {
                Self.logger.warning("Rejected pagination URL with untrusted domain: \(pageURL)")
                throw OANDAError.invalidURL
            }
            let pageData = try await makeRequest(url: pageURL)
            let pageResponse = try JSONDecoder.oanda.decode(TransactionPageResponse.self, from: pageData)
            allTransactions.append(contentsOf: pageResponse.transactions)
        }

        Self.logger.info("Fetched \(allTransactions.count) transactions from OANDA")
        return allTransactions
    }

    /// Only HTTPS URLs on oanda.com (or a subdomain) may receive the API token.
    static func isTrustedOANDAURL(_ string: String) -> Bool {
        guard let url = URL(string: string), url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else { return false }
        return host == "oanda.com" || host.hasSuffix(".oanda.com")
    }

    /// OANDA account IDs look like "101-004-1234567-001": letters, digits and dashes only.
    static func isValidAccountID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }

    private func makeRequest(url: String) async throws -> Data {
        guard Self.isValidAccountID(accountID) else {
            throw OANDAError.invalidURL
        }
        guard Self.isTrustedOANDAURL(url), let requestURL = URL(string: url) else {
            throw OANDAError.invalidURL
        }

        var request = URLRequest(url: requestURL)
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await Self.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OANDAError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw OANDAError.unauthorized
            }
            Self.logger.error("OANDA API error: HTTP \(httpResponse.statusCode)")
            throw OANDAError.httpError(httpResponse.statusCode)
        }

        guard let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
              contentType.contains("json") else {
            throw OANDAError.invalidResponse
        }

        return data
    }

    // MARK: - Map to Trade

    private func mapTransactionsToTrades(_ transactions: [OANDATransaction]) -> [Trade] {
        // Group ORDER_FILL transactions into trade pairs (open + close)
        // OANDA uses tradeOpened/tradeClosed to link them
        var openTrades: [String: OANDATransaction] = [:]
        var trades: [Trade] = []
        let now = Date()

        for tx in transactions {
            if let tradeOpened = tx.tradeOpened {
                // This is an opening fill
                openTrades[tradeOpened.tradeID] = tx
            }

            if let tradeClosed = tx.tradesClosed {
                // This is a closing fill — match with opening
                for closed in tradeClosed {
                    guard let openTx = openTrades[closed.tradeID] else { continue }

                    let symbol = cleanSymbol(tx.instrument ?? openTx.instrument ?? "")
                    let units = abs(Double(openTx.units ?? "0") ?? 0)
                    let lots = units / 100_000 // Standard lot conversion

                    let direction: TradeDirection = (Double(openTx.units ?? "0") ?? 0) > 0 ? .buy : .sell

                    let openPrice = Decimal(string: openTx.price ?? "0") ?? 0
                    let closePrice = Decimal(string: tx.price ?? "0") ?? 0
                    let profit = Decimal(string: closed.realizedPL ?? "0") ?? 0

                    let openTime = parseOANDADate(openTx.time) ?? now
                    let closeTime = parseOANDADate(tx.time) ?? now
                    let duration = Int(saturating: closeTime.timeIntervalSince(openTime) / 60)

                    let ticket = Int64(closed.tradeID) ?? Int64(Int(saturating: now.timeIntervalSince1970))

                    let trade = Trade(
                        id: nil,
                        ticket: ticket,
                        symbol: symbol,
                        direction: direction,
                        lots: lots,
                        openTime: openTime,
                        closeTime: closeTime,
                        durationMin: max(0, duration),
                        openPrice: openPrice,
                        closePrice: closePrice,
                        sl: 0,
                        tp: 0,
                        netProfit: profit,
                        maePips: 0,
                        mfePips: 0,
                        rMultiple: 0,
                        session: openTime.tradingSession,
                        dayOfWeek: openTime.shortDayName,
                        hour: openTime.utcHour,
                        rangeSize: 0,
                        sweepDepth: 0,
                        usedFVG: false,
                        volRegime: .med,
                        hitBreakeven: false,
                        scaledIn: false,
                        magic: 0,
                        comment: "OANDA",
                        timeToMFEMin: 0,
                        slDistPips: 0,
                        slippagePips: 0,
                        postClose15m: 0,
                        postClose30m: 0,
                        biasAtEntry: .neutral,
                        importedAt: now
                    )
                    trades.append(trade)
                    openTrades.removeValue(forKey: closed.tradeID)
                }
            }
        }

        Self.logger.info("Mapped \(trades.count) completed trades from OANDA")
        return trades
    }

    private func cleanSymbol(_ raw: String) -> String {
        raw.uppercased()
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: "_", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private func parseOANDADate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    // MARK: - Response Types

    struct AccountSummary: Codable, Sendable {
        let id: String
        let currency: String
        let balance: String
    }

    private struct AccountSummaryResponse: Codable {
        let account: AccountSummary
    }

    struct OANDATransaction: Codable, Sendable {
        let id: String?
        let type: String?
        let time: String?
        let instrument: String?
        let units: String?
        let price: String?
        let tradeOpened: TradeRef?
        let tradesClosed: [TradeClosedRef]?
    }

    struct TradeRef: Codable, Sendable {
        let tradeID: String
    }

    struct TradeClosedRef: Codable, Sendable {
        let tradeID: String
        let realizedPL: String?
    }

    private struct TransactionPageResponse: Codable {
        let transactions: [OANDATransaction]
    }

    // MARK: - Errors

    enum OANDAError: LocalizedError {
        case invalidURL
        case invalidResponse
        case unauthorized
        case httpError(Int)
        case noAccount

        var errorDescription: String? {
            switch self {
            case .invalidURL: "Invalid OANDA API URL"
            case .invalidResponse: "Invalid response from OANDA"
            case .unauthorized: "Invalid API token — check your OANDA API key"
            case .httpError(let code): "OANDA API error (HTTP \(code))"
            case .noAccount: "No OANDA account ID configured"
            }
        }
    }
}

// MARK: - JSON Decoder

private extension JSONDecoder {
    static let oanda: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        return decoder
    }()
}
