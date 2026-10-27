import Foundation
import os

/// Manages live price data from the user's selected source.
/// Wraps streaming providers and REST polling behind a unified interface.
@Observable
@MainActor
final class LiveDataManager {
    private static let logger = Logger(subsystem: "com.dojix", category: "LiveData")

    /// Current connection status
    private(set) var status: StreamingStatus = .disconnected

    /// Latest prices keyed by symbol
    private(set) var latestPrices: [String: PriceUpdate] = [:]

    /// Active data source
    private(set) var activeSource: LiveDataSource = .twelveDataREST

    /// Whether the active source is real-time streaming
    var isStreaming: Bool { activeSource.isStreaming && status == .connected }

    private var activeProvider: (any LivePriceProvider)?
    private var priceTask: Task<Void, Never>?
    private var symbols: [String] = []

    // MARK: - Public API

    /// Start receiving prices for the given symbols using the user's selected source
    func start(symbols: [String]) async {
        self.symbols = symbols
        let source = KeychainHelper.liveDataSource
        activeSource = source

        await stop()

        guard let provider = createProvider(for: source) else {
            status = .error(source.requiredKeyDescription + " not configured")
            Self.logger.warning("No API key for \(source.displayName)")
            return
        }

        activeProvider = provider
        status = .connecting

        do {
            try await provider.subscribe(symbols: symbols)

            // Listen for price updates
            priceTask = Task { [weak self] in
                for await update in provider.prices {
                    guard !Task.isCancelled else { break }
                    self?.record(update)
                }
                // Stream ended
                if !Task.isCancelled {
                    self?.status = .disconnected
                }
            }
        } catch is CancellationError {
            return
        } catch {
            status = .error(error.localizedDescription)
            Self.logger.error("Failed to start \(source.displayName): \(error.localizedDescription)")
        }
    }

    /// Test hook: mark a source as active without connecting to it
    func setActiveSourceForTesting(_ source: LiveDataSource) {
        activeSource = source
    }

    /// Store a price update from the active provider
    func record(_ update: PriceUpdate) {
        latestPrices[update.symbol] = update
        status = .connected
    }

    /// Stop all price streaming and wait for provider to disconnect
    func stop() async {
        priceTask?.cancel()
        priceTask = nil

        if let provider = activeProvider {
            await provider.disconnect()
        }
        activeProvider = nil
        status = .disconnected
    }

    /// Switch to a different data source and restart
    func switchSource(to source: LiveDataSource) async {
        KeychainHelper.liveDataSource = source
        await start(symbols: symbols)
    }

    /// Check if the required API key is configured for a given source
    func hasRequiredKey(for source: LiveDataSource) -> Bool {
        switch source {
        case .twelveDataREST, .twelveDataWebSocket:
            guard let key = KeychainHelper.twelveDataAPIKey else { return false }
            return !key.isEmpty
        case .oandaStreaming:
            guard let token = KeychainHelper.oandaAPIToken,
                  let accountId = KeychainHelper.oandaAccountID else { return false }
            return !token.isEmpty && !accountId.isEmpty
        case .polygonWebSocket:
            guard let key = KeychainHelper.polygonAPIKey else { return false }
            return !key.isEmpty
        case .mt5Direct:
            let mt5Path = Configuration.mt5PrimaryFolder
            let filePath = (mt5Path as NSString).appendingPathComponent("DojixPrices.json")
            return FileManager.default.fileExists(atPath: filePath)
        }
    }

    // MARK: - Provider Factory

    private func createProvider(for source: LiveDataSource) -> (any LivePriceProvider)? {
        switch source {
        case .twelveDataREST:
            guard let key = KeychainHelper.twelveDataAPIKey, !key.isEmpty else { return nil }
            return TwelveDataRESTProvider(apiKey: key)

        case .twelveDataWebSocket:
            guard let key = KeychainHelper.twelveDataAPIKey, !key.isEmpty else { return nil }
            return TwelveDataWebSocket(apiKey: key)

        case .oandaStreaming:
            guard let token = KeychainHelper.oandaAPIToken, !token.isEmpty,
                  let accountId = KeychainHelper.oandaAccountID, !accountId.isEmpty else { return nil }
            return OANDAStreamService(apiToken: token, accountId: accountId, isLive: KeychainHelper.oandaIsLive)

        case .polygonWebSocket:
            guard let key = KeychainHelper.polygonAPIKey, !key.isEmpty else { return nil }
            return PolygonWebSocket(apiKey: key)

        case .mt5Direct:
            let mt5Path = Configuration.mt5PrimaryFolder
            return MT5FileProvider(mt5Path: mt5Path)
        }
    }
}

// MARK: - REST Polling Provider (wraps existing TwelveDataService)

/// Adapts the existing TwelveDataService REST polling to the LivePriceProvider protocol
actor TwelveDataRESTProvider: LivePriceProvider {
    private let apiKey: String
    private let pollInterval: TimeInterval = 120 // 2 minutes
    private var continuation: AsyncStream<PriceUpdate>.Continuation?
    private var pollTask: Task<Void, Never>?
    private(set) var status: StreamingStatus = .disconnected

    nonisolated let prices: AsyncStream<PriceUpdate>

    init(apiKey: String) {
        self.apiKey = apiKey
        var stored: AsyncStream<PriceUpdate>.Continuation?
        self.prices = AsyncStream { stored = $0 }
        self.continuation = stored
    }

    func subscribe(symbols: [String]) async throws {
        status = .connected
        let service = TwelveDataService(apiKey: apiKey)

        pollTask = Task {
            while !Task.isCancelled {
                do {
                    let quotes = try await service.getQuotes(symbols: symbols)
                    for quote in quotes {
                        let update = PriceUpdate(
                            symbol: quote.symbol,
                            bid: quote.close - 0.00005,
                            ask: quote.close + 0.00005,
                            timestamp: quote.timestamp
                        )
                        continuation?.yield(update)
                    }
                } catch is CancellationError {
                    break
                } catch {
                    // Continue polling on transient errors
                }
                try? await Task.sleep(for: .seconds(pollInterval))
            }
        }
    }

    func disconnect() async {
        pollTask?.cancel()
        pollTask = nil
        continuation?.finish()
        continuation = nil
        status = .disconnected
    }
}
