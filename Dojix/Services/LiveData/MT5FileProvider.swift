import Foundation
import os

/// Reads live prices from a JSON file written by the DojixPriceFeed MT5 EA.
/// Watches the file for changes via DispatchSource — no API key needed.
actor MT5FileProvider: LivePriceProvider {
    private static let logger = Logger(subsystem: "com.dojix", category: "MT5File")

    private let filePath: String
    private var watchTask: Task<Void, Never>?
    private var continuation: AsyncStream<PriceUpdate>.Continuation?

    nonisolated let prices: AsyncStream<PriceUpdate>

    init(mt5Path: String) {
        self.filePath = (mt5Path as NSString).appendingPathComponent("DojixPrices.json")

        var stored: AsyncStream<PriceUpdate>.Continuation?
        self.prices = AsyncStream { stored = $0 }
        self.continuation = stored
    }

    func subscribe(symbols _: [String]) async throws {
        guard FileManager.default.fileExists(atPath: filePath) else {
            Self.logger.warning("DojixPrices.json not found at \(self.filePath)")
            throw MT5FileError.fileNotFound
        }

        Self.logger.info("Watching \(self.filePath)")

        // Read once immediately
        readAndEmit()

        // Watch for file changes
        watchTask = Task { [weak self] in
            guard let self else { return }
            await self.watchFile()
        }
    }

    func disconnect() async {
        watchTask?.cancel()
        watchTask = nil
        continuation?.finish()
        continuation = nil
        Self.logger.info("Disconnected")
    }

    // MARK: - File Watching

    private func watchFile() async {
        guard let fd = open(filePath, O_EVTONLY) as Int32?, fd >= 0 else {
            Self.logger.error("Failed to open file descriptor for watching")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename],
            queue: DispatchQueue.global(qos: .utility)
        )

        let stream = AsyncStream<Void> { continuation in
            source.setEventHandler { continuation.yield() }
            source.setCancelHandler {
                close(fd)
                continuation.finish()
            }
            source.resume()
        }

        for await _ in stream {
            guard !Task.isCancelled else { break }
            readAndEmit()
        }

        source.cancel()
    }

    // MARK: - JSON Parsing

    /// Largest price file read. Any MQL5 program can write to MT5's Files folders, so a
    /// huge file must not be loaded into memory on every change (the EA writes a few KB).
    static let maximumFileSize = 256 * 1024

    /// The price file's bytes, or nil if it is missing or over `maximumFileSize`.
    private func readCappedFile() -> Data? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: filePath),
              let size = (attributes[.size] as? NSNumber)?.intValue, size <= Self.maximumFileSize,
              let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: filePath)) else {
            Self.logger.warning("DojixPrices.json missing or over \(Self.maximumFileSize) bytes; ignored")
            return nil
        }
        defer { try? handle.close() }
        // Bounded read as well: the file may grow between the size check and the read.
        guard let data = try? handle.read(upToCount: Self.maximumFileSize + 1),
              data.count <= Self.maximumFileSize else { return nil }
        return data
    }

    private func readAndEmit() {
        guard let data = readCappedFile(),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pricesArray = json["prices"] as? [[String: Any]] else {
            return
        }

        let timestamp: Date
        if let ts = json["ts"] as? String {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy.MM.dd HH:mm:ss"
            fmt.timeZone = TimeZone(identifier: "UTC")
            timestamp = fmt.date(from: ts) ?? Date()
        } else {
            timestamp = Date()
        }

        for price in pricesArray {
            guard let symbol = price["s"] as? String,
                  let bid = price["b"] as? Double,
                  let ask = price["a"] as? Double else { continue }

            let update = PriceUpdate(symbol: symbol, bid: bid, ask: ask, timestamp: timestamp)
            continuation?.yield(update)
        }
    }

    // MARK: - Errors

    enum MT5FileError: LocalizedError {
        case fileNotFound

        var errorDescription: String? {
            "DojixPrices.json not found. Attach the DojixPriceFeed EA in MT5."
        }
    }
}
