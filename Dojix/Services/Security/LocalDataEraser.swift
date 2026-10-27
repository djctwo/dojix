import Foundation
import GRDB
import os

/// "Erase all local data and start fresh" — the only way past a forgotten app-lock
/// password. It never just removes the lock: the journal, screenshots and every
/// stored key are destroyed first, so forgetting (or guessing at) the password
/// never exposes the data the lock was protecting.
enum LocalDataEraser {
    private static let logger = Logger(subsystem: "com.dojix", category: "Eraser")

    /// Erase everything: the rows in memory (if the journal is open), the encrypted
    /// database file and every copy next to it (older builds' `.pre-restore-backup`,
    /// `.unreadable-*`, `-wal`/`-shm`), all screenshots, and every Keychain item
    /// (database key, wrapped key, API keys), plus settings older builds kept in
    /// UserDefaults. Works while locked: nothing is decrypted.
    static func eraseAll(database: DatabaseManager, screenshotsDirectory: URL,
                         defaults: UserDefaults = .standard) throws {
        if database.isLoaded {
            try database.dbQueue.write { db in
                try db.execute(sql: "DELETE FROM trades")
                try db.execute(sql: "DELETE FROM strategy_checkpoints")
                try db.execute(sql: "DELETE FROM settings")
            }
            // Rebuild the in-memory file so deleted rows don't linger in free pages.
            try database.dbQueue.vacuum()
        }
        try database.unloadWithoutSaving()
        try database.deleteFilesOnDisk()
        if FileManager.default.fileExists(atPath: screenshotsDirectory.path) {
            try FileManager.default.removeItem(at: screenshotsDirectory)
        }
        KeychainHelper.deleteAll()
        PropFirmSettings.removeLegacyDefaults(defaults)
        logger.info("All local data erased")
    }
}
