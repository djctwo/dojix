import Foundation
import GRDB
import os

extension DatabaseManager {
    // MARK: - Migrations

    /// Every migration identifier this build knows (backups may only contain these).
    static let knownMigrations: Set<String> = [
        "v1_createTrades", "v2_addTradeNotes", "v3_addTradeTags",
        "v4_addEmotionCommissionScreenshotsChecklist", "v5_createStrategyCheckpoints",
        "v1_createSettings",
    ]

    static func runMigrations(on writer: some DatabaseWriter) throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_createTrades") { db in
            try db.create(table: "trades") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("ticket", .integer).notNull().unique()
                t.column("symbol", .text).notNull()
                t.column("direction", .text).notNull()
                t.column("lots", .double).notNull()
                t.column("openTime", .datetime).notNull()
                t.column("closeTime", .datetime).notNull()
                t.column("durationMin", .integer).notNull()
                t.column("openPrice", .text).notNull()   // Decimal stored as text
                t.column("closePrice", .text).notNull()
                t.column("sl", .text).notNull()
                t.column("tp", .text).notNull()
                t.column("netProfit", .text).notNull()
                t.column("maePips", .double).notNull()
                t.column("mfePips", .double).notNull()
                t.column("rMultiple", .double).notNull()
                t.column("session", .text).notNull()
                t.column("dayOfWeek", .text).notNull()
                t.column("hour", .integer).notNull()
                t.column("rangeSize", .double).notNull()
                t.column("sweepDepth", .double).notNull()
                t.column("usedFVG", .boolean).notNull()
                t.column("volRegime", .text).notNull()
                t.column("hitBreakeven", .boolean).notNull()
                t.column("scaledIn", .boolean).notNull()
                t.column("magic", .integer).notNull()
                t.column("comment", .text).notNull().defaults(to: "")
                t.column("timeToMFEMin", .integer).notNull().defaults(to: 0)
                t.column("slDistPips", .double).notNull().defaults(to: 0)
                t.column("slippagePips", .double).notNull().defaults(to: 0)
                t.column("postClose15m", .double).notNull().defaults(to: 0)
                t.column("postClose30m", .double).notNull().defaults(to: 0)
                t.column("biasAtEntry", .text).notNull().defaults(to: "NEUTRAL")
                t.column("importedAt", .datetime).notNull()
            }

            // Indexes for common queries
            try db.create(index: "idx_trades_symbol", on: "trades", columns: ["symbol"])
            try db.create(index: "idx_trades_session", on: "trades", columns: ["session"])
            try db.create(index: "idx_trades_openTime", on: "trades", columns: ["openTime"])
            try db.create(index: "idx_trades_hour", on: "trades", columns: ["hour"])
        }

        migrator.registerMigration("v2_addTradeNotes") { db in
            try db.alter(table: "trades") { t in
                t.add(column: "notes", .text).notNull().defaults(to: "")
            }
        }

        migrator.registerMigration("v3_addTradeTags") { db in
            try db.alter(table: "trades") { t in
                t.add(column: "tags", .text).notNull().defaults(to: "")
            }
        }

        migrator.registerMigration("v4_addEmotionCommissionScreenshotsChecklist") { db in
            try db.alter(table: "trades") { t in
                t.add(column: "emotion", .text).notNull().defaults(to: "")
                t.add(column: "commission", .text).notNull().defaults(to: "0")
                t.add(column: "swap", .text).notNull().defaults(to: "0")
                t.add(column: "screenshots", .text).notNull().defaults(to: "")
                t.add(column: "checklistData", .text).notNull().defaults(to: "")
            }
        }

        migrator.registerMigration("v5_createStrategyCheckpoints") { db in
            try db.create(table: "strategy_checkpoints") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("date", .date).notNull()
                t.column("title", .text).notNull()
                t.column("description", .text).notNull().defaults(to: "")
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(index: "idx_checkpoints_date", on: "strategy_checkpoints", columns: ["date"])
        }

        migrator.registerMigration("v1_createSettings") { db in
            try db.create(table: "settings") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }
        }

        try migrator.migrate(writer)
        Logger(subsystem: "com.dojix", category: "Database").info("Database migrations complete")
    }
}
