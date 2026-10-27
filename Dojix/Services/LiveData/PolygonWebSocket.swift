import Foundation
import os

/// Real-time forex price streaming via Polygon.io WebSocket API
actor PolygonWebSocket: LivePriceProvider {
    private static let logger = Logger(subsystem: "com.dojix", category: "PolygonWS")

    private let apiKey: String
    private let endpoint = URL(string: "wss://socket.polygon.io/forex")!
    private let maxRetries = 10
    private let maxBackoff: TimeInterval = 60

    private var task: URLSessionWebSocketTask?
    private var continuation: AsyncStream<PriceUpdate>.Continuation?
    private var subscribedSymbols: [String] = []
    private var retryCount = 0

    nonisolated let prices: AsyncStream<PriceUpdate>
    private(set) var status: StreamingStatus = .disconnected

    init(apiKey: String) {
        self.apiKey = apiKey
        var stored: AsyncStream<PriceUpdate>.Continuation?
        self.prices = AsyncStream { stored = $0 }
        self.continuation = stored
    }

    // MARK: - LivePriceProvider

    func subscribe(symbols: [String]) async throws {
        subscribedSymbols = symbols
        retryCount = 0
        try await connect()
    }

    func disconnect() async {
        status = .disconnected
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        continuation?.finish()
        Self.logger.info("Disconnected")
    }

    // MARK: - Connection

    private func connect() async throws {
        status = .connecting
        Self.logger.info("Connecting to Polygon.io WebSocket")

        let session = SecureSession.make(timeout: 30)
        let wsTask = session.webSocketTask(with: endpoint)
        self.task = wsTask
        wsTask.resume()

        try await authenticate(wsTask)
        try await sendSubscription(wsTask)

        status = .connected
        retryCount = 0
        Self.logger.info("Connected and subscribed to \(self.subscribedSymbols.count) symbols")

        await receiveLoop(wsTask)
    }

    private func authenticate(_ wsTask: URLSessionWebSocketTask) async throws {
        let authObj: [String: String] = ["action": "auth", "params": apiKey]
        let authData = try JSONSerialization.data(withJSONObject: authObj)
        let authPayload = String(data: authData, encoding: .utf8) ?? ""
        try await wsTask.send(.string(authPayload))

        let message = try await wsTask.receive()
        guard case .string(let text) = message,
              let data = text.data(using: .utf8),
              let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = array.first,
              let authStatus = first["status"] as? String,
              authStatus == "auth_success" else {
            status = .error("Authentication failed")
            throw PolygonError.authFailed
        }
        Self.logger.info("Authenticated with Polygon.io")
    }

    private func sendSubscription(_ wsTask: URLSessionWebSocketTask) async throws {
        let prefixed = subscribedSymbols.map { "C.\($0)" }.joined(separator: ",")
        let subObj: [String: String] = ["action": "subscribe", "params": prefixed]
        let subData = try JSONSerialization.data(withJSONObject: subObj)
        let payload = String(data: subData, encoding: .utf8) ?? ""
        try await wsTask.send(.string(payload))
        Self.logger.debug("Subscribed: \(prefixed)")
    }

    // MARK: - Receive Loop

    private func receiveLoop(_ wsTask: URLSessionWebSocketTask) async {
        while status == .connected {
            do {
                let message = try await wsTask.receive()
                handleMessage(message)
            } catch {
                guard status == .connected else { return }
                Self.logger.warning("Receive error: \(error.localizedDescription)")
                await attemptReconnect()
                return
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        guard case .string(let text) = message,
              let data = text.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return
        }

        for item in array {
            guard let ev = item["ev"] as? String, ev == "C",
                  let pair = item["p"] as? String,
                  let bid = item["b"] as? Double,
                  let ask = item["a"] as? Double,
                  let timestampMs = item["t"] as? Double else {
                continue
            }

            let update = PriceUpdate(
                symbol: pair,
                bid: bid,
                ask: ask,
                timestamp: Date(timeIntervalSince1970: timestampMs / 1000)
            )
            continuation?.yield(update)
        }
    }

    // MARK: - Reconnection

    private func attemptReconnect() async {
        task?.cancel(with: .abnormalClosure, reason: nil)
        task = nil

        while retryCount < maxRetries {
            retryCount += 1
            status = .reconnecting(attempt: retryCount)
            let delay = min(pow(2.0, Double(retryCount)) , maxBackoff)
            Self.logger.info("Reconnecting (attempt \(self.retryCount)) in \(delay)s")

            try? await Task.sleep(for: .seconds(delay))

            guard status.isActive else { return }

            do {
                try await connect()
                return
            } catch {
                Self.logger.warning("Reconnect attempt \(self.retryCount) failed: \(error.localizedDescription)")
            }
        }

        status = .error("Max reconnection attempts (\(maxRetries)) exceeded")
        Self.logger.error("Gave up reconnecting after \(self.maxRetries) attempts")
    }

    // MARK: - Errors

    enum PolygonError: LocalizedError {
        case authFailed
        case connectionLost

        var errorDescription: String? {
            switch self {
            case .authFailed: "Polygon.io authentication failed. Check your API key."
            case .connectionLost: "WebSocket connection lost."
            }
        }
    }
}
