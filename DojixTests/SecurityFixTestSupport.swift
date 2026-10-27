import CryptoKit
import Foundation
import GRDB
import Security
@testable import Dojix

/// In-memory stand-in for the Keychain, so key wrapping is tested without touching one.
final class MemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: String] = [:]
    /// When set, every read returns this status (simulates a locked/unreadable Keychain).
    var forcedReadStatus: OSStatus?

    func read(_ account: String) -> (value: String?, status: OSStatus) {
        lock.lock(); defer { lock.unlock() }
        if let forcedReadStatus { return (nil, forcedReadStatus) }
        guard let value = items[account] else { return (nil, errSecItemNotFound) }
        return (value, errSecSuccess)
    }

    @discardableResult
    func write(_ account: String, _ value: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        items[account] = value
        return true
    }

    func delete(_ account: String) {
        lock.lock(); defer { lock.unlock() }
        items[account] = nil
    }

    func value(_ account: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return items[account]
    }
}

/// Fictional trades and scratch folders for the security tests.
enum SecFixture {
    static func trade(
        ticket: Int64,
        symbol: String = "EURUSD",
        lots: Double = 0.10,
        netProfit: Decimal = 10,
        durationMin: Int = 60,
        closeTime: Date = Date(timeIntervalSince1970: 1_767_225_600),
        screenshots: String = ""
    ) -> Trade {
        var trade = Trade(
            id: nil, ticket: ticket, symbol: symbol, direction: .buy,
            lots: lots, openTime: closeTime.addingTimeInterval(-3600),
            closeTime: closeTime, durationMin: durationMin,
            openPrice: 1.1, closePrice: 1.101, sl: 1.09, tp: 1.12,
            netProfit: netProfit, maePips: 3, mfePips: 8,
            rMultiple: 1, session: .london, dayOfWeek: "Thu", hour: 10,
            rangeSize: 20, sweepDepth: 4, usedFVG: false, volRegime: .med,
            hitBreakeven: false, scaledIn: false, magic: 0, comment: "Sample (fictional)",
            timeToMFEMin: 10, slDistPips: 10, slippagePips: 0,
            postClose15m: 0, postClose30m: 0, biasAtEntry: .neutral,
            importedAt: closeTime
        )
        trade.screenshots = screenshots
        return trade
    }

    /// A new empty folder under the system temp directory (removed by `cleanup`).
    static func scratchDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("dojix-secfix-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Whether any file in `dir` (recursively) is a readable SQLite database or WAL.
    static func plaintextFiles(in dir: URL) -> [String] {
        guard let walker = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { return [] }
        var found: [String] = []
        for case let url as URL in walker {
            guard let data = try? Data(contentsOf: url) else { continue }
            if DatabaseEncryption.isPlainSQLite(data) || DatabaseEncryption.isPlainWAL(data) {
                found.append(url.lastPathComponent)
            }
        }
        return found
    }

    /// A plaintext journal as an older build left it: WAL mode with rows still in the
    /// `-wal` file (not checkpointed), as after a crash.
    static func writeLegacyPlaintextJournal(at path: String, trades: [Trade]) throws {
        var config = GRDB.Configuration()
        config.foreignKeysEnabled = true
        let pool = try DatabasePool(path: path, configuration: config)
        try DatabaseManager.runMigrations(on: pool)
        try pool.write { db in
            for trade in trades {
                var row = trade
                try row.insert(db)
            }
        }
        // Copy the files while the pool is open, so the -wal still holds the rows.
        let tmp = path + ".copying"
        for suffix in ["", "-wal", "-shm"] where FileManager.default.fileExists(atPath: path + suffix) {
            try? FileManager.default.removeItem(atPath: tmp + suffix)
            try FileManager.default.copyItem(atPath: path + suffix, toPath: tmp + suffix)
        }
        try pool.close()
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: path + suffix)
            if FileManager.default.fileExists(atPath: tmp + suffix) {
                try FileManager.default.moveItem(atPath: tmp + suffix, toPath: path + suffix)
            }
        }
    }
}

