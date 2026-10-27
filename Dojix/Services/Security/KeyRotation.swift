import CryptoKit
import Foundation
import os

/// Replacing the database key (App Lock turned on, password changed, or a lock set by
/// an older build migrated), so that a bare key that may survive in an old Keychain or
/// disk backup can't decrypt the journal any more.
///
/// Crash-safe order:
/// 1. `vault.beginRotation`: the new key is stored wrapped *together with* the old one
///    (one atomic Keychain update); only then is the bare key deleted.
/// 2. The journal is re-saved with the new key; stray copies and screenshots are re-sealed.
/// 3. `vault.finishRotation`: only the new key stays (wrapped). This runs only when the
///    journal file on disk opens with the new key and every file that needed the old key
///    was re-sealed; otherwise both keys stay stored and the next unlock tries again
///    (`finishAfterUnlock`).
/// If the process stops anywhere, the next unlock finds both keys, opens whatever is still
/// sealed with the old one and completes steps 2–3.
///
/// Once step 1 has succeeded the new key (and password) is in force, so nothing after it
/// is reported as a failure: the result says whether the rotation is complete or will be
/// finished at the next unlock.
enum KeyRotation {
    private static let logger = Logger(subsystem: "com.dojix", category: "KeyRotation")

    /// How a rotation ended once the new key was stored (the new password is in force).
    enum Outcome: Equatable, Sendable {
        /// Every file is sealed with the new key; only it is stored.
        case complete
        /// The new key (and password) is in force, but some file still needs the old
        /// key, so both stay stored; the next unlock finishes the job.
        case finishesOnNextUnlock
    }

    /// Steps 1–3 for a loaded journal currently sealed with `oldKey`. Throws only when
    /// step 1 fails (then nothing changed). If step 1 was accepted but couldn't be
    /// confirmed, nothing else is done and the outcome is `finishesOnNextUnlock`.
    /// `beforeFinishing`: test seam, runs right before step 3 is decided.
    @discardableResult
    static func rotate(vault: DatabaseKeyVault, database: DatabaseManager, screenshots: ScreenshotManager,
                       oldKey: SymmetricKey, password: String,
                       beforeFinishing: (@Sendable () -> Void)? = nil) throws -> Outcome {
        let newKey: SymmetricKey
        do {
            newKey = try vault.beginRotation(from: oldKey, password: password)
        } catch DatabaseKeyVault.VaultError.unconfirmed {
            // The Keychain took [new, old] but couldn't be read back. Most likely the new
            // password is in force, so this isn't reported as a failure; the journal stays
            // sealed with the old key (stored either way) and the next unlock finishes.
            logger.error("The new key could not be read back; the rotation finishes at the next unlock")
            return .finishesOnNextUnlock
        }
        do {
            try database.rekey(to: newKey)
        } catch {
            // Locked meanwhile, or the save failed: the journal still needs the old key,
            // which stays stored next to the new one.
            logger.error("Journal not re-sealed yet; the rotation finishes at the next unlock: \(error.localizedDescription)")
            return .finishesOnNextUnlock
        }
        return finish(vault: vault, database: database, screenshots: screenshots,
                      from: oldKey, to: newKey, password: password, beforeFinishing: beforeFinishing)
    }

    /// After an unlock that found two keys (an interrupted rotation, or the migration of
    /// an older build's lock): the journal is already loaded (`load(key:previousKey:)`),
    /// so re-save it with the current key, re-seal the remaining files, keep only the
    /// current key when nothing needs the previous one any more.
    @discardableResult
    static func finishAfterUnlock(keys: DatabaseKeyVault.UnwrappedKeys, password: String, vault: DatabaseKeyVault,
                                  database: DatabaseManager, screenshots: ScreenshotManager) throws -> Outcome {
        guard let previous = keys.previous else { return .complete }
        try database.rekey(to: keys.current)
        return finish(vault: vault, database: database, screenshots: screenshots,
                      from: previous, to: keys.current, password: password, beforeFinishing: nil)
    }

    /// Before the key or password changes again: complete a pending rotation, or throw
    /// `rotationPending` (nothing is changed) so its older key is never dropped.
    static func finishPending(keys: DatabaseKeyVault.UnwrappedKeys, password: String, vault: DatabaseKeyVault,
                              database: DatabaseManager, screenshots: ScreenshotManager) throws {
        guard keys.previous != nil else { return }
        let outcome = try finishAfterUnlock(keys: keys, password: password, vault: vault,
                                            database: database, screenshots: screenshots)
        guard outcome == .complete else { throw DatabaseKeyVault.VaultError.rotationPending }
    }

    /// Step 2 for the files next to the journal, then step 3 if nothing needs `old` any more.
    private static func finish(vault: DatabaseKeyVault, database: DatabaseManager, screenshots: ScreenshotManager,
                               from old: SymmetricKey, to new: SymmetricKey, password: String,
                               beforeFinishing: (@Sendable () -> Void)?) -> Outcome {
        let pending = resealFiles(database: database, screenshots: screenshots, from: old, to: new)
        beforeFinishing?()
        guard pending.isEmpty else {
            logger.error("\(pending.count) file(s) could not be re-sealed; keeping the previous key until the next unlock")
            return .finishesOnNextUnlock
        }
        guard journalOpens(at: database.databasePath, with: new) else {
            logger.error("The journal on disk does not open with the new key; keeping the previous key")
            return .finishesOnNextUnlock
        }
        do {
            try vault.finishRotation(new, password: password)
        } catch {
            logger.error("Could not drop the previous key: \(error.localizedDescription)")
            return .finishesOnNextUnlock
        }
        return .complete
    }

    /// Whether the journal file at `path` exists and decrypts with `key` to a database.
    static func journalOpens(at path: String, with key: SymmetricKey) -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let opened = try? DatabaseEncryption.openJournal(data, key: key) else { return false }
        return DatabaseEncryption.isPlainSQLite(opened.image)
    }

    /// Re-seal stray journal copies and screenshots from `old` to `new`. Returns the
    /// files that may still need `old` (could not be read or re-written).
    @discardableResult
    static func resealFiles(database: DatabaseManager, screenshots: ScreenshotManager,
                            from old: SymmetricKey, to new: SymmetricKey) -> [URL] {
        DatabaseEncryption.resealStrayCopies(besides: database.databasePath, from: old, to: new)
            + screenshots.reseal(from: old, to: new)
    }
}
