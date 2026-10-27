import Foundation
import GRDB
import os

/// All trade database operations go through this repository
final class TradeRepository: Sendable {
    private let database: DatabaseManager
    private static let logger = Logger(subsystem: "com.dojix", category: "TradeRepository")

    init(database: DatabaseManager) {
        self.database = database
    }

    // MARK: - Write

    /// Insert a trade, skipping if ticket already exists. Returns true if inserted.
    @discardableResult
    func insertIfNew(_ trade: Trade) throws -> Bool {
        try database.dbQueue.write { db in
            let exists = try Trade.filter(Column("ticket") == trade.ticket).fetchCount(db) > 0
            if exists { return false }
            var t = trade.sanitizedForStorage()
            try t.insert(db)
            return true
        }
    }

    /// Bulk insert trades, skipping duplicates. Returns count of newly inserted trades.
    func bulkInsert(_ trades: [Trade]) throws -> Int {
        try database.dbQueue.write { db in
            var insertedCount = 0
            for trade in trades {
                let exists = try Trade.filter(Column("ticket") == trade.ticket).fetchCount(db) > 0
                if exists { continue }
                var t = trade.sanitizedForStorage()
                try t.insert(db)
                insertedCount += 1
            }
            Self.logger.info("Inserted \(insertedCount) of \(trades.count) trades")
            return insertedCount
        }
    }

    /// Delete only the fictional sample trades (see DemoDataGenerator). Returns count deleted.
    @discardableResult
    func deleteSampleTrades() throws -> Int {
        try database.dbQueue.write { db in
            try Trade
                .filter(Column("comment") == DemoDataGenerator.sampleComment)
                .filter(Column("ticket") >= DemoDataGenerator.ticketBase)
                .deleteAll(db)
        }
    }

    /// Delete all trades (for testing/reset)
    func deleteAll() throws {
        _ = try database.dbQueue.write { db in
            try Trade.deleteAll(db)
        }
    }

    /// Update trade notes
    func updateNotes(tradeId: Int64, notes: String) throws {
        try database.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE trades SET notes = ? WHERE id = ?",
                arguments: [notes, tradeId]
            )
        }
    }

    /// Update trade tags
    func updateTags(tradeId: Int64, tags: String) throws {
        try database.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE trades SET tags = ? WHERE id = ?",
                arguments: [tags, tradeId]
            )
        }
    }

    /// Update trade emotion
    func updateEmotion(tradeId: Int64, emotion: String) throws {
        try database.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE trades SET emotion = ? WHERE id = ?",
                arguments: [emotion, tradeId]
            )
        }
    }

    /// Update trade commission and swap (clamped to the range every stored amount keeps,
    /// so a backup of the journal still passes restore validation).
    func updateCosts(tradeId: Int64, commission: Decimal, swap: Decimal) throws {
        try database.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE trades SET commission = ?, swap = ? WHERE id = ?",
                arguments: [Trade.money(commission).description, Trade.money(swap).description, tradeId]
            )
        }
    }

    /// Update trade screenshots
    func updateScreenshots(tradeId: Int64, screenshots: String) throws {
        try database.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE trades SET screenshots = ? WHERE id = ?",
                arguments: [screenshots, tradeId]
            )
        }
    }

    /// Update trade checklist data (JSON string)
    func updateChecklist(tradeId: Int64, checklistData: String) throws {
        try database.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE trades SET checklistData = ? WHERE id = ?",
                arguments: [checklistData, tradeId]
            )
        }
    }

    // MARK: - Read

    /// Fetch all trades, ordered by close time descending
    func fetchAll() throws -> [Trade] {
        try database.dbQueue.read { db in
            try Trade.order(Column("closeTime").desc).fetchAll(db)
        }
    }

    /// Fetch trades filtered by symbol
    func fetchBySymbol(_ symbol: String) throws -> [Trade] {
        try database.dbQueue.read { db in
            try Trade.filter(Column("symbol") == symbol)
                .order(Column("closeTime").desc)
                .fetchAll(db)
        }
    }

    /// Fetch trades within a date range
    func fetchByDateRange(from: Date, to: Date) throws -> [Trade] {
        try database.dbQueue.read { db in
            try Trade.filter(Column("closeTime") >= from && Column("closeTime") <= to)
                .order(Column("closeTime").desc)
                .fetchAll(db)
        }
    }

    /// Fetch trades by session
    func fetchBySession(_ session: TradingSession) throws -> [Trade] {
        try database.dbQueue.read { db in
            try Trade.filter(Column("session") == session.rawValue)
                .order(Column("closeTime").desc)
                .fetchAll(db)
        }
    }

    /// Total trade count
    func count() throws -> Int {
        try database.dbQueue.read { db in
            try Trade.fetchCount(db)
        }
    }

    /// Check if a ticket exists
    func ticketExists(_ ticket: Int64) throws -> Bool {
        try database.dbQueue.read { db in
            try Trade.filter(Column("ticket") == ticket).fetchCount(db) > 0
        }
    }

    // MARK: - Aggregates

    /// Total net profit across all trades
    func totalProfit() throws -> Double {
        try database.dbQueue.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT CAST(SUM(CAST(netProfit AS REAL)) AS REAL) AS total FROM trades")
            return row?["total"] ?? 0.0
        }
    }

    /// Profit by symbol
    func profitBySymbol() throws -> [(symbol: String, profit: Double, count: Int)] {
        try database.dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT symbol,
                       CAST(SUM(CAST(netProfit AS REAL)) AS REAL) as profit,
                       COUNT(*) as count
                FROM trades
                GROUP BY symbol
                ORDER BY profit DESC
            """)
            return rows.map { (
                symbol: $0["symbol"] as String,
                profit: $0["profit"] as Double,
                count: $0["count"] as Int
            )}
        }
    }

    /// Profit by session
    func profitBySession() throws -> [(session: String, profit: Double, count: Int)] {
        try database.dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT session,
                       CAST(SUM(CAST(netProfit AS REAL)) AS REAL) as profit,
                       COUNT(*) as count
                FROM trades
                GROUP BY session
                ORDER BY profit DESC
            """)
            return rows.map { (
                session: $0["session"] as String,
                profit: $0["profit"] as Double,
                count: $0["count"] as Int
            )}
        }
    }

    /// Profit by hour
    func profitByHour() throws -> [(hour: Int, profit: Double, count: Int)] {
        try database.dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT hour,
                       CAST(SUM(CAST(netProfit AS REAL)) AS REAL) as profit,
                       COUNT(*) as count
                FROM trades
                GROUP BY hour
                ORDER BY hour
            """)
            return rows.map { (
                hour: $0["hour"] as Int,
                profit: $0["profit"] as Double,
                count: $0["count"] as Int
            )}
        }
    }

    /// Equity curve data — cumulative P&L over time
    func equityCurve() throws -> [(date: Date, cumulative: Double)] {
        try database.dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT closeTime,
                       CAST(netProfit AS REAL) as profit
                FROM trades
                ORDER BY closeTime
            """)
            var cumulative = 0.0
            return rows.map { row in
                let profit: Double = row["profit"]
                cumulative += profit
                return (date: row["closeTime"] as Date, cumulative: cumulative)
            }
        }
    }

    // MARK: - Observation (Reactive)

    /// Observe all trades for SwiftUI binding. Returns cancellable.
    @MainActor
    func observeAll(
        onError: @escaping @Sendable (Error) -> Void,
        onChange: @escaping @Sendable ([Trade]) -> Void
    ) -> AnyDatabaseCancellable {
        ValueObservation
            .tracking { db in
                try Trade.order(Column("closeTime").desc).fetchAll(db)
            }
            .start(in: database.dbQueue, onError: onError, onChange: onChange)
    }

    /// Observe trade count. Returns cancellable.
    @MainActor
    func observeCount(
        onError: @escaping @Sendable (Error) -> Void,
        onChange: @escaping @Sendable (Int) -> Void
    ) -> AnyDatabaseCancellable {
        ValueObservation
            .tracking { db in
                try Trade.fetchCount(db)
            }
            .start(in: database.dbQueue, onError: onError, onChange: onChange)
    }
}
