import Foundation
import GRDB

/// Key-value settings kept inside the encrypted journal (`settings` table): values that
/// say something about the user's trading. They are encrypted, locked by App Lock,
/// included in backups and erased with the journal, unlike UserDefaults.
final class SettingsRepository: Sendable {
    private let database: DatabaseManager

    init(database: DatabaseManager) {
        self.database = database
    }

    /// The stored value, or nil if there is none.
    func string(for key: String) throws -> String? {
        try database.dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = ?", arguments: [key])
        }
    }

    /// Store several values in one transaction.
    func set(_ values: [String: String]) throws {
        guard !values.isEmpty else { return }
        try database.dbQueue.write { db in
            for (key, value) in values {
                try db.execute(sql: "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
                               arguments: [key, value])
            }
        }
    }
}

/// Prop-firm challenge settings shown by `PropFirmTracker`. The account size reveals how
/// much capital the user trades, so these live in the encrypted journal
/// (`SettingsRepository`), not in the plaintext preferences file.
struct PropFirmSettings: Equatable, Sendable {
    var accountSize = 100_000.0
    /// Percent of the account size
    var profitTarget = 8.0
    /// Percent of the account size
    var maxDailyLoss = 5.0
    /// Percent of the account size
    var maxTotalDrawdown = 10.0

    /// Storage keys (also the UserDefaults keys older builds used).
    enum Key {
        static let accountSize = "propFirm_accountSize"
        static let profitTarget = "propFirm_profitTarget"
        static let maxDailyLoss = "propFirm_maxDailyLoss"
        static let maxTotalDrawdown = "propFirm_maxTotalDrawdown"
        static let all = [accountSize, profitTarget, maxDailyLoss, maxTotalDrawdown]
    }

    /// Largest account size accepted.
    static let accountSizeLimit = 1_000_000_000_000.0

    /// Whether `value` is acceptable for `key` (finite, positive, within range).
    static func isValid(_ value: Double, for key: String) -> Bool {
        guard value.isFinite, value > 0 else { return false }
        return key == Key.accountSize ? value <= accountSizeLimit : value <= 100
    }

    /// The stored settings; a missing or invalid value (for example from a restored
    /// backup) falls back to its default.
    static func load(from repository: SettingsRepository) throws -> PropFirmSettings {
        var settings = PropFirmSettings()
        func stored(_ key: String) throws -> Double? {
            guard let text = try repository.string(for: key), let value = Double(text),
                  isValid(value, for: key) else { return nil }
            return value
        }
        if let value = try stored(Key.accountSize) { settings.accountSize = value }
        if let value = try stored(Key.profitTarget) { settings.profitTarget = value }
        if let value = try stored(Key.maxDailyLoss) { settings.maxDailyLoss = value }
        if let value = try stored(Key.maxTotalDrawdown) { settings.maxTotalDrawdown = value }
        return settings
    }

    /// Store the valid values (an invalid one keeps what was stored before).
    func save(to repository: SettingsRepository) throws {
        try repository.set(Self.validValues([
            Key.accountSize: accountSize, Key.profitTarget: profitTarget,
            Key.maxDailyLoss: maxDailyLoss, Key.maxTotalDrawdown: maxTotalDrawdown,
        ]))
    }

    /// Move values an older build kept in UserDefaults into the journal (unless the
    /// journal already has one), then delete them from UserDefaults. Nothing is deleted
    /// if the journal write fails.
    static func migrateLegacyDefaults(_ defaults: UserDefaults = .standard,
                                      into repository: SettingsRepository) throws {
        var found: [String: Double] = [:]
        for key in Key.all where defaults.object(forKey: key) != nil {
            if try repository.string(for: key) == nil {
                found[key] = defaults.double(forKey: key)
            }
        }
        try repository.set(validValues(found))
        removeLegacyDefaults(defaults)
    }

    /// Delete the values older builds kept in UserDefaults ("Erase all local data").
    static func removeLegacyDefaults(_ defaults: UserDefaults = .standard) {
        for key in Key.all {
            defaults.removeObject(forKey: key)
        }
    }

    private static func validValues(_ values: [String: Double]) -> [String: String] {
        values.reduce(into: [:]) { result, entry in
            if isValid(entry.value, for: entry.key) { result[entry.key] = String(entry.value) }
        }
    }
}
