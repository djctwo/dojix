import Foundation

/// A real-time price update from any streaming source
struct PriceUpdate: Sendable {
    let symbol: String
    let bid: Double
    let ask: Double
    let mid: Double
    let spread: Double
    let timestamp: Date

    init(symbol: String, bid: Double, ask: Double, timestamp: Date = Date()) {
        self.symbol = symbol
        self.bid = bid
        self.ask = ask
        self.mid = (bid + ask) / 2
        self.spread = ask - bid
        self.timestamp = timestamp
    }
}

/// Connection status for streaming providers
enum StreamingStatus: Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case error(String)

    var displayText: String {
        switch self {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting..."
        case .connected: "Streaming"
        case .reconnecting(let attempt): "Reconnecting (\(attempt))..."
        case .error(let msg): "Error: \(msg)"
        }
    }

    var isActive: Bool {
        switch self {
        case .connected, .connecting, .reconnecting: true
        default: false
        }
    }
}

/// Available live data sources
enum LiveDataSource: String, CaseIterable, Sendable, Identifiable {
    case twelveDataREST = "twelve_data_rest"
    case twelveDataWebSocket = "twelve_data_ws"
    case oandaStreaming = "oanda_stream"
    case polygonWebSocket = "polygon_ws"
    case mt5Direct = "mt5_direct"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .twelveDataREST: "Twelve Data (Polling)"
        case .twelveDataWebSocket: "Twelve Data (WebSocket)"
        case .oandaStreaming: "OANDA (Streaming)"
        case .polygonWebSocket: "Polygon.io (WebSocket)"
        case .mt5Direct: "MT5 Direct (File)"
        }
    }

    var description: String {
        switch self {
        case .twelveDataREST: "Polls every 2 minutes. Free tier: 800 req/day."
        case .twelveDataWebSocket: "Real-time streaming. Requires paid Twelve Data plan."
        case .oandaStreaming: "Real-time bid/ask from OANDA. Free with trading account."
        case .polygonWebSocket: "Real-time streaming. Requires Polygon.io subscription."
        case .mt5Direct: "Real-time from MT5 via DojixPriceFeed EA. No API key needed."
        }
    }

    var isStreaming: Bool {
        self != .twelveDataREST
    }

    /// Which API key this source requires
    var requiredKeyDescription: String {
        switch self {
        case .twelveDataREST, .twelveDataWebSocket: "Twelve Data API Key"
        case .oandaStreaming: "OANDA API Token"
        case .polygonWebSocket: "Polygon.io API Key"
        case .mt5Direct: "MT5 Common Files path"
        }
    }
}

/// Protocol for all live price providers (both polling and streaming)
protocol LivePriceProvider: Sendable {
    /// Start receiving price updates for the given symbols
    func subscribe(symbols: [String]) async throws

    /// Stop all streaming
    func disconnect() async

    /// Async stream of price updates
    nonisolated var prices: AsyncStream<PriceUpdate> { get }
}
