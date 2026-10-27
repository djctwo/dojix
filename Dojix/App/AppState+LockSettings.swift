import CryptoKit
import Foundation

/// Settings > Security: turning App Lock on or off and changing its password.
///
/// Rules that keep the journal decryptable whatever else happens meanwhile (a lock from
/// a closed lid, idle time or Cmd-H; a failing disk):
/// - A lock during the change is safe: `DatabaseManager.rekey` and `unload` are ordered
///   on the database queue, and the old key is dropped only once the file on disk opens
///   with the new one (`KeyRotation`).
/// - Once the new key is stored, the change is reported as made (with "finishes at the
///   next unlock" when files still need the old key), never as failed.
/// - A rotation that is still pending is finished before the key changes again, so its
///   older key is never dropped while a file needs it.
/// - One change at a time: while any key operation runs (an unlock, or a change started
///   in another window), Enable / Change Password / Disable refuse with `busy`.
extension AppState {
    enum AppLockChangeError: LocalizedError {
        case alreadyOn
        case lockedMeanwhile
        case busy

        var errorDescription: String? {
            switch self {
            case .alreadyOn:
                "App Lock is already on. Use Change Password instead."
            case .lockedMeanwhile:
                "Dojix locked before App Lock could be turned off, so App Lock is still on. Unlock and try again."
            case .busy:
                "Another App Lock change or unlock is still running (maybe in another window). Try again when it has finished."
            }
        }
    }

    /// Turn App Lock on: a NEW database key replaces the current one (the journal and
    /// screenshots are re-sealed with it) and is stored only wrapped with `password`.
    /// A lock requested while this runs happens as soon as App Lock is on.
    @MainActor
    func enableAppLock(password: String) async throws -> KeyRotation.Outcome {
        guard !isAppLockOn else { throw AppLockChangeError.alreadyOn }
        guard keyOperationsInFlight == 0 else { throw AppLockChangeError.busy }
        guard let oldKey = database.currentKey else { throw DatabaseKeyVault.VaultError.corrupt }
        let vault = self.vault
        let database = self.database
        let screenshots = self.screenshots
        let whileChangingKey = hooks.whileChangingKey
        beginKeyOperation()
        beginDeferringLocks()
        defer {
            endDeferringLocks()
            endKeyOperation()
        }
        do {
            let outcome = try await Task.detached(priority: .userInitiated) {
                await whileChangingKey?()
                return try KeyRotation.rotate(vault: vault, database: database, screenshots: screenshots,
                                              oldKey: oldKey, password: password)
            }.value
            isAppLockOn = true
            vault.removeLegacyPasswordHash()
            return outcome
        } catch {
            // Nothing was stored; if the Keychain can't tell, count the lock as on (fail closed).
            isAppLockOn = AppLock.isEnabled(vault: vault)
            throw error
        }
    }

    /// Turn App Lock off (needs the current password): the key becomes a bare Keychain
    /// item again. The Keychain is changed on the main actor right after checking that no
    /// lock happened during the password check, so a lock screen is never left up with
    /// App Lock off (it couldn't be unlocked).
    @MainActor
    func disableAppLock(password: String) async throws {
        guard keyOperationsInFlight == 0 else { throw AppLockChangeError.busy }
        let vault = self.vault
        let database = self.database
        let screenshots = self.screenshots
        let whileChangingKey = hooks.whileChangingKey
        beginKeyOperation()
        defer { endKeyOperation() }
        let key = try await Task.detached(priority: .userInitiated) {
            let keys = try vault.unwrapKeys(password: password)
            try KeyRotation.finishPending(keys: keys, password: password, vault: vault,
                                          database: database, screenshots: screenshots)
            await whileChangingKey?()
            return keys.current
        }.value
        guard !isLocked else { throw AppLockChangeError.lockedMeanwhile }
        try vault.storePlain(verified: key)
        isAppLockOn = false
        vault.removeLegacyPasswordHash()
    }

    /// Change the App Lock password (needs the current one). The database key is
    /// rotated too, so a copy of the old wrapped key plus the old password opens nothing.
    @MainActor
    func changeAppLockPassword(current: String, new: String) async throws -> KeyRotation.Outcome {
        guard keyOperationsInFlight == 0 else { throw AppLockChangeError.busy }
        let vault = self.vault
        let database = self.database
        let screenshots = self.screenshots
        let whileChangingKey = hooks.whileChangingKey
        beginKeyOperation()
        defer { endKeyOperation() }
        return try await Task.detached(priority: .userInitiated) {
            let keys = try vault.unwrapKeys(password: current)
            try KeyRotation.finishPending(keys: keys, password: current, vault: vault,
                                          database: database, screenshots: screenshots)
            await whileChangingKey?()
            return try KeyRotation.rotate(vault: vault, database: database, screenshots: screenshots,
                                          oldKey: keys.current, password: new)
        }.value
    }
}
