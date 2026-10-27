import Foundation
import os

/// Real-time forex price streaming via Twelve Data WebSocket API
actor TwelveDataWebSocket: LivePriceProvider {

    // MARK: - Properties

    private let apiKey: String
    private let logger = Logger(subsystem: "com.dojix", category: "TwelveDataWS")
    private let endpoint = URL(string: "wss://ws.twelvedata.com/v1/quotes/price")!

    private var webSocketTask: URLSessionWebSocketTask?
    private var continuation: AsyncStream<PriceUpdate>.Continuation?
    private var _prices: AsyncStream<PriceUpdate>?
    private var _status: StreamingStatus = .disconnected
    private var retryCount = 0
    private var subscribedSymbols: [String] = []

    private let maxRetries = 10
    private let maxBackoff: TimeInterval = 60

    nonisolated var prices: AsyncStream<PriceUpdate> { _pricesStream }
    private let _pricesStream: AsyncStream<PriceUpdate>
    private let _priceContinuation: AsyncStream<PriceUpdate>.Continuation

    var status: StreamingStatus { _status }

    // MARK: - Init

    init(apiKey: String) {
        self.apiKey = apiKey
        let (stream, continuation) = AsyncStream<PriceUpdate>.makeStream()
        self._pricesStream = stream
        self._priceContinuation = continuation
    }

    // MARK: - LivePriceProvider

    func subscribe(symbols: [String]) async throws {
        guard !symbols.isEmpty else { return }
        subscribedSymbols = symbols
        retryCount = 0
        _status = .connecting
        try await connect()
    }

    func disconnect() async {
        _status = .disconnected
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        subscribedSymbols = []
        logger.info("Disconnected")
    }

    // MARK: - Connection

    private func connect() async throws {
        let session = SecureSession.make(timeout: 30)
        let task = session.webSocketTask(with: endpoint)
        self.webSocketTask = task
        task.resume()

        try await sendSubscription()
        _status = .connected
        retryCount = 0
        logger.info("Connected, streaming \(self.subscribedSymbols.joined(separator: ", "))")
        listenForMessages()
    }

    private func sendSubscription() async throws {
        let symbolList = subscribedSymbols.joined(separator: ",")
        let payload: [String: Any] = [
            "action": "subscribe",
            "params": ["symbols": symbolList, "apikey": apiKey]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotParseResponse)
        }
        try await webSocketTask?.send(.string(jsonString))
        logger.debug("Sent subscribe for \(symbolList)")
    }

    // MARK: - Message Loop

    private func listenForMessages() {
        guard let task = webSocketTask else { return }
        Task { [weak task] in
            guard let task else { return }
            do {
                let message = try await task.receive()
                await handleMessage(message)
                listenForMessages()
            } catch {
                await handleDisconnection(error: error)
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            parseJSON(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                parseJSON(text)
            }
        @unknown default:
            logger.warning("Unknown message type received")
        }
    }

    private func parseJSON(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = json["event"] as? String else {
            return
        }

        switch event {
        case "heartbeat":
            respondToHeartbeat()
        case "price":
            guard let symbol = json["symbol"] as? String,
                  let bidStr = json["bid"] as? String,
                  let askStr = json["ask"] as? String,
                  let bid = Double(bidStr),
                  let ask = Double(askStr) else {
                logger.debug("Malformed price message: \(text)")
                return
            }
            let ts: Date
            if let epoch = json["timestamp"] as? TimeInterval {
                ts = Date(timeIntervalSince1970: epoch)
            } else {
                ts = Date()
            }
            let update = PriceUpdate(symbol: symbol, bid: bid, ask: ask, timestamp: ts)
            _priceContinuation.yield(update)
        default:
            logger.debug("Unhandled event: \(event)")
        }
    }

    private func respondToHeartbeat() {
        Task {
            let payload = #"{"event":"heartbeat"}"#
            try? await webSocketTask?.send(.string(payload))
        }
    }

    // MARK: - Reconnection

    private func handleDisconnection(error: Error) {
        guard _status != .disconnected else { return }
        logger.error("WebSocket error: \(error.localizedDescription)")

        guard retryCount < maxRetries else {
            _status = .error("Max retries (\(maxRetries)) exceeded")
            logger.error("Giving up after \(self.maxRetries) retries")
            return
        }

        retryCount += 1
        _status = .reconnecting(attempt: retryCount)
        let delay = min(pow(2.0, Double(retryCount)), maxBackoff)
        logger.info("Reconnecting in \(delay)s (attempt \(self.retryCount)/\(self.maxRetries))")

        Task {
            try? await Task.sleep(for: .seconds(delay))
            guard _status.isActive else { return }
            do {
                try await connect()
            } catch {
                await handleDisconnection(error: error)
            }
        }
    }
}
