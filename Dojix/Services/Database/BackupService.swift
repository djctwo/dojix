import Foundation
import GRDB
import os

/// Handles database backup and restore for user data protection
enum BackupService {
    private static let logger = Logger(subsystem: "com.dojix", category: "Backup")

    /// Largest backup file Dojix will read.
    static let maximumBackupSize = 512 * 1024 * 1024
    /// Most rows accepted per table from a backup.
    static let maximumRows = 2_000_000

    // MARK: - Export

    /// Write the current journal as a backup file (owner-only, 0600, symlink-safe).
    /// With a `password`, the file is encrypted (`BackupEncryption`, PBKDF2-SHA256 with
    /// `iterations` rounds + AES-256-GCM); without one it is a standard SQLite file that
    /// anyone who gets it can read.
    static func writeBackup(of database: DatabaseManager, to destination: URL, password: String? = nil,
                            iterations: UInt32 = BackupEncryption.defaultIterations) throws {
        let image = try database.dbQueue.writeWithoutTransaction { db -> Data in
            // Locked (or erased) meanwhile: never write the empty placeholder as "the
            // backup". Checked on the database queue, where locking also happens.
            guard database.isLoaded else { throw DatabaseEncryption.EncryptionError.keyUnavailable }
            return try DatabaseManager.serialize(db)
        }
        if let password {
            try OwnerOnlyFile.write(try BackupEncryption.seal(image, password: password, iterations: iterations),
                                    to: destination)
        } else {
            try OwnerOnlyFile.write(image, to: destination)
        }
    }

    // MARK: - Restore

    /// What a restore brought back.
    struct RestoreSummary: Equatable {
        let trades: Int
        let checkpoints: Int
    }

    /// Validated rows of a backup, ready to replace the journal.
    struct Contents {
        var trades: [Trade]
        var checkpoints: [StrategyCheckpoint]
        var settings: [(key: String, value: String)]
    }

    /// Validate `source` (decrypting it with `password` if it is password-protected),
    /// then swap in a fresh journal built from its rows.
    ///
    /// The backup file is never copied over the journal: it is opened in memory
    /// (read-only first), its schema must match exactly what Dojix's own migrator creates,
    /// and every row is checked. A brand-new database is then created with Dojix's
    /// migrator, only the validated, cleaned rows are inserted into it, and that database
    /// replaces the journal in one step. Anything wrong = nothing changes.
    static func restore(from source: URL, password: String? = nil, into database: DatabaseManager) throws -> RestoreSummary {
        let contents = try validatedContents(of: source, password: password)
        let fresh = try DatabaseQueue()
        try DatabaseManager.runMigrations(on: fresh)
        try fresh.write { db in
            for trade in contents.trades {
                var row = trade
                try row.insert(db)
            }
            for checkpoint in contents.checkpoints {
                var row = checkpoint
                try row.insert(db)
            }
            for setting in contents.settings {
                try db.execute(sql: "INSERT INTO settings (key, value) VALUES (?, ?)",
                               arguments: [setting.key, setting.value])
            }
        }
        let freshImage = try fresh.writeWithoutTransaction { db in try DatabaseManager.serialize(db) }
        try database.replaceContents(with: freshImage)
        logger.info("Backup restored: \(contents.trades.count) trades")
        return RestoreSummary(trades: contents.trades.count, checkpoints: contents.checkpoints.count)
    }

    /// Read and check a backup file without touching the journal. A password-protected
    /// backup needs its `password` (`BackupError.passwordRequired` / `.wrongPassword`).
    static func validatedContents(of source: URL, password: String? = nil) throws -> Contents {
        let attributes = try? FileManager.default.attributesOfItem(atPath: source.path)
        if let size = attributes?[.size] as? Int, size > maximumBackupSize {
            throw BackupError.tooLarge
        }
        guard let fileData = try? Data(contentsOf: source), fileData.count <= maximumBackupSize else {
            throw BackupError.notADojixBackup
        }
        let data: Data
        if BackupEncryption.kind(of: fileData).needsPassword {
            guard let password, !password.isEmpty else { throw BackupError.passwordRequired }
            data = try BackupEncryption.open(fileData, password: password)
        } else {
            data = fileData
        }
        guard data.count <= maximumBackupSize, DatabaseEncryption.isPlainSQLite(data) else {
            throw BackupError.notADojixBackup
        }

        let candidate = try DatabaseQueue(configuration: candidateConfiguration())
        // 1. Read-only: integrity and schema checks before anything runs on it.
        do {
            try candidate.writeWithoutTransaction { db in
                try DatabaseManager.deserialize(data, into: db, readOnly: true)
            }
        } catch {
            throw BackupError.notADojixBackup
        }
        let applied = try candidate.read { db -> Set<String> in
            let check = try String.fetchAll(db, sql: "PRAGMA quick_check")
            guard check == ["ok"] else { throw BackupError.damaged }
            try checkSchema(db)
            return Set(try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations"))
        }
        guard applied.isSubset(of: DatabaseManager.knownMigrations) else {
            throw BackupError.newerVersion
        }

        // 2. Bring an older backup up to the current schema (in memory only).
        try candidate.writeWithoutTransaction { db in
            try DatabaseManager.deserialize(data, into: db)
        }
        do {
            try DatabaseManager.runMigrations(on: candidate)
        } catch {
            throw BackupError.notADojixBackup
        }
        // The migrated schema must be exactly Dojix's: same tables, columns (types, NOT
        // NULL, defaults, keys), indexes and nothing else (no triggers, views, extra
        // columns, expression indexes or generated columns).
        let reference = try DatabaseQueue()
        try DatabaseManager.runMigrations(on: reference)
        let expected = try reference.read { try schemaSignature($0) }
        guard try candidate.read({ try schemaSignature($0) }) == expected else {
            throw BackupError.notADojixBackup
        }

        // 3. Every row: decodable, within the bounds Dojix itself writes, then cleaned.
        return try candidate.read { db in
            for table in ["trades", "strategy_checkpoints", "settings"] {
                let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0
                guard count <= maximumRows else { throw BackupError.tooLarge }
            }
            let trades: [Trade]
            let checkpoints: [StrategyCheckpoint]
            let settings: [Row]
            do {
                trades = try Trade.fetchAll(db)
                checkpoints = try StrategyCheckpoint.fetchAll(db)
                settings = try Row.fetchAll(db, sql: "SELECT key, value FROM settings")
            } catch {
                throw BackupError.invalidValues("a row could not be read")
            }
            var cleanTrades: [Trade] = []
            cleanTrades.reserveCapacity(trades.count)
            for trade in trades {
                let violations = trade.storageViolations()
                guard violations.isEmpty else {
                    throw BackupError.invalidValues("trade \(trade.ticket): \(violations.joined(separator: ", "))")
                }
                cleanTrades.append(trade.sanitizedForRestore())
            }
            let cleanCheckpoints = checkpoints.map { checkpoint -> StrategyCheckpoint in
                var c = checkpoint
                c.title = Trade.stripControls(c.title, keepingLineBreaks: false)
                c.description = Trade.stripControls(c.description, keepingLineBreaks: true)
                return c
            }
            let cleanSettings = try settings.map { row -> (key: String, value: String) in
                guard let key = row["key"] as String?, let value = row["value"] as String? else {
                    throw BackupError.invalidValues("settings")
                }
                return (Trade.stripControls(key, keepingLineBreaks: false), value)
            }
            return Contents(trades: cleanTrades, checkpoints: cleanCheckpoints, settings: cleanSettings)
        }
    }

    private static func candidateConfiguration() -> GRDB.Configuration {
        var config = GRDB.Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA trusted_schema = OFF")
            try db.execute(sql: "PRAGMA cell_size_check = ON")
        }
        return config
    }

    /// A structural description of every schema object: tables with each column's
    /// declared type, NOT NULL, default and key position (hidden/generated columns
    /// included), each index with its columns and uniqueness, foreign keys, plus the list
    /// of objects. Independent of how the CREATE statements were spelled.
    static func schemaSignature(_ db: Database) throws -> [String] {
        var lines: [String] = []
        let objects = try Row.fetchAll(db, sql: "SELECT type, name, tbl_name FROM sqlite_master ORDER BY type, name")
        for object in objects {
            let type: String = object["type"] ?? ""
            let name: String = object["name"] ?? ""
            let table: String = object["tbl_name"] ?? ""
            lines.append("\(type) \(name) on \(table)")
            guard type == "table" else { continue }
            let quoted = name.replacingOccurrences(of: "\"", with: "\"\"")
            for column in try Row.fetchAll(db, sql: "PRAGMA table_xinfo(\"\(quoted)\")") {
                lines.append("  column \(column["cid"] as Int? ?? -1) \(column["name"] as String? ?? "") "
                    + "\(column["type"] as String? ?? "") notnull=\(column["notnull"] as Int? ?? -1) "
                    + "default=\(column["dflt_value"] as String? ?? "NULL") pk=\(column["pk"] as Int? ?? -1) "
                    + "hidden=\(column["hidden"] as Int? ?? -1)")
            }
            for index in try Row.fetchAll(db, sql: "PRAGMA index_list(\"\(quoted)\")") {
                let indexName: String = index["name"] ?? ""
                lines.append("  index \(indexName) unique=\(index["unique"] as Int? ?? -1) "
                    + "origin=\(index["origin"] as String? ?? "") partial=\(index["partial"] as Int? ?? -1)")
                let quotedIndex = indexName.replacingOccurrences(of: "\"", with: "\"\"")
                for part in try Row.fetchAll(db, sql: "PRAGMA index_xinfo(\"\(quotedIndex)\")") {
                    lines.append("    part \(part["seqno"] as Int? ?? -1) cid=\(part["cid"] as Int? ?? -9) "
                        + "name=\(part["name"] as String? ?? "") desc=\(part["desc"] as Int? ?? -1) "
                        + "coll=\(part["coll"] as String? ?? "") key=\(part["key"] as Int? ?? -1)")
                }
            }
            for key in try Row.fetchAll(db, sql: "PRAGMA foreign_key_list(\"\(quoted)\")") {
                lines.append("  fk \(key["table"] as String? ?? "") \(key["from"] as String? ?? "")->\(key["to"] as String? ?? "")")
            }
        }
        // CHECK constraints and collations are only visible in the CREATE statement
        let statements = try String.fetchAll(db, sql: "SELECT sql FROM sqlite_master WHERE sql IS NOT NULL")
        if statements.contains(where: { $0.range(of: "CHECK", options: .caseInsensitive) != nil
            || $0.range(of: "COLLATE", options: .caseInsensitive) != nil }) {
            lines.append("check-or-collate")
        }
        return lines
    }

    /// Only Dojix's own tables and indexes; no views or triggers (they could run SQL
    /// when the rows are read or written).
    private static func checkSchema(_ db: Database) throws {
        let allowedTables: Set<String> = ["trades", "strategy_checkpoints", "settings", "grdb_migrations", "sqlite_sequence"]
        let allowedIndexes: Set<String> = [
            "idx_trades_symbol", "idx_trades_session", "idx_trades_openTime", "idx_trades_hour", "idx_checkpoints_date",
        ]
        let objects = try Row.fetchAll(db, sql: "SELECT type, name FROM sqlite_master")
        var tables: Set<String> = []
        for object in objects {
            let type: String = object["type"] ?? ""
            let name: String = object["name"] ?? ""
            switch type {
            case "table":
                guard allowedTables.contains(name) else { throw BackupError.notADojixBackup }
                tables.insert(name)
            case "index":
                guard allowedIndexes.contains(name) || name.hasPrefix("sqlite_autoindex_") else {
                    throw BackupError.notADojixBackup
                }
            default:
                throw BackupError.notADojixBackup
            }
        }
        guard tables.contains("trades"), tables.contains("grdb_migrations") else {
            throw BackupError.notADojixBackup
        }
    }

    /// Get the database file size
    static func databaseSize(at path: String) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64 else {
            return "Unknown"
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    // MARK: - Errors

    enum BackupError: LocalizedError, Equatable {
        case passwordRequired
        case wrongPassword
        case notADojixBackup
        case damaged
        case newerVersion
        case tooLarge
        case invalidValues(String)

        var errorDescription: String? {
            switch self {
            case .notADojixBackup: "That file isn't a Dojix backup. Your current data was not changed."
            case .passwordRequired: "This backup is protected with a password. Enter it to restore. Your current data was not changed."
            case .wrongPassword: "Wrong password for this backup (or the file was changed). Your current data was not changed."
            case .damaged: "That backup file is damaged. Your current data was not changed."
            case .newerVersion: "That backup was made by a newer version of Dojix. Your current data was not changed."
            case .tooLarge: "That backup file is too large to restore. Your current data was not changed."
            case .invalidValues(let detail): "That backup contains values Dojix never writes (\(detail)), so it was not restored. Your current data was not changed."
            }
        }
    }
}
