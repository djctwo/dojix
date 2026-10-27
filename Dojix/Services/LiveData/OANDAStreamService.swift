import Foundation
import os

/// Real-time forex price streaming from OANDA v20 Pricing Stream API
actor OANDAStreamService: LivePriceProvider {
    private static let logger = Logger(subsystem: "com.dojix", category: "OANDAStream")

    private let apiToken: String
    private let accountId: String
    private let baseURL: String
    private let session: URLSession

    private var streamTask: Task<Void, Never>?
    private var continuation: AsyncStream<PriceUpdate>.Continuation?
    private let _prices: AsyncStream<PriceUpdate>
    private var _status: StreamingStatus = .disconnected

    private let maxRetries = 10
    private let maxBackoff: TimeInterval = 60

    // MARK: - LivePriceProvider Conformance

    nonisolated var prices: AsyncStream<PriceUpdate> { _prices }

    var status: StreamingStatus { _status }

    // MARK: - Init

    init(apiToken: String, accountId: String, isLive: Bool) {
        self.apiToken = apiToken
        self.accountId = accountId
        self.baseURL = isLive
            ? "https://stream-fxtrade.oanda.com"
            : "https://stream-fxpractice.oanda.com"
        self.session = SecureSession.make(timeout: 30)

        var captured: AsyncStream<PriceUpdate>.Continuation?
        self._prices = AsyncStream { captured = $0 }
        self.continuation = captured
    }

    // MARK: - Subscribe / Disconnect

    func subscribe(symbols: [String]) async throws {
        guard !symbols.isEmpty else { return }
        await disconnect()
        guard OANDAService.isValidAccountID(accountId) else {
            throw OANDAStreamError.invalidURL
        }

        let instruments = symbols.map { $0.replacingOccurrences(of: "/", with: "_") }
        let instrumentsParam = instruments.joined(separator: ",")

        guard var components = URLComponents(
            string: "\(baseURL)/v3/accounts/\(accountId)/pricing/stream"
        ) else {
            throw OANDAStreamError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "instruments", value: instrumentsParam)]

        guard let url = components.url,
              OANDAService.isTrustedOANDAURL(url.absoluteString) else {
            throw OANDAStreamError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")

        _status = .connecting
        Self.logger.info("Subscribing to \(instruments.count) instrument(s)")

        streamTask = Task { [weak self] in
            await self?.streamWithReconnect(request: request)
        }
    }

    func disconnect() async {
        streamTask?.cancel()
        streamTask = nil
        _status = .disconnected
        Self.logger.info("Disconnected")
    }


    // MARK: - Streaming Loop

    private func streamWithReconnect(request: URLRequest) async {
        var attempt = 0
        while !Task.isCancelled, attempt < maxRetries {
            do {
                try await readStream(request: request)
                // Clean exit (server closed connection) — reconnect
            } catch is CancellationError {
                break
            } catch {
                Self.logger.error("Stream error: \(error.localizedDescription)")
            }

            attempt += 1
            _status = .reconnecting(attempt: attempt)
            let delay = min(pow(2.0, Double(attempt)), maxBackoff)
            Self.logger.info("Reconnecting in \(delay)s (attempt \(attempt)/\(self.maxRetries))")
            try? await Task.sleep(for: .seconds(delay))
        }

        if attempt >= maxRetries {
            _status = .error("Max reconnect attempts reached")
            Self.logger.error("Gave up after \(self.maxRetries) reconnect attempts")
        }
    }

    private func readStream(request: URLRequest) async throws {
        let (bytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OANDAStreamError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw OANDAStreamError.httpError(httpResponse.statusCode)
        }

        _status = .connected
        Self.logger.info("Stream connected")

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard !line.isEmpty else { continue }
            parseLine(line)
        }
    }

    // MARK: - JSON Parsing

    private func parseLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        guard type == "PRICE" else { return } // skip HEARTBEATs

        guard let instrument = json["instrument"] as? String,
              let bids = json["bids"] as? [[String: Any]],
              let asks = json["asks"] as? [[String: Any]],
              let bidStr = bids.first?["price"] as? String,
              let askStr = asks.first?["price"] as? String,
              let bid = Double(bidStr),
              let ask = Double(askStr) else {
            Self.logger.warning("Malformed PRICE payload")
            return
        }

        let timestamp: Date
        if let timeStr = json["time"] as? String {
            timestamp = ISO8601DateFormatter().date(from: timeStr) ?? Date()
        } else {
            timestamp = Date()
        }

        let symbol = instrument.replacingOccurrences(of: "_", with: "/")
        let update = PriceUpdate(symbol: symbol, bid: bid, ask: ask, timestamp: timestamp)
        continuation?.yield(update)
    }

    // MARK: - Errors

    enum OANDAStreamError: LocalizedError {
        case invalidURL
        case invalidResponse
        case httpError(Int)

        var errorDescription: String? {
            switch self {
            case .invalidURL: "Invalid OANDA stream URL"
            case .invalidResponse: "Invalid response from OANDA"
            case .httpError(let code): "OANDA stream returned HTTP \(code)"
            }
        }
    }
}
