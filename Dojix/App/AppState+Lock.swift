import CryptoKit
import Foundation
import GRDB

/// Opening the journal, App Lock and "erase all".
///
/// The journal (in memory, see `DatabaseManager`) is only opened with the database key.
/// With App Lock on, that key exists only wrapped with the lock password, so nothing is
/// decrypted until the password has been entered.
extension AppState {
    enum UnlockResult: Equatable {
        case unlocked
        case wrongPassword
        case failed(String)
        /// The password was right, but the journal file is older than the last one this
        /// Mac saved: `olderJournal` is set and the app stays locked until the user decides.
        case olderJournal
    }

    // MARK: - Launch

    /// Called once from `init`: open the journal, or show the lock screen.
    /// `instanceLockDirectory`: the data folder this copy must hold alone (nil: no check).
    func startUp(instanceLockDirectory: URL?) {
        if let instanceLockDirectory {
            switch InstanceLock.acquire(in: instanceLockDirectory) {
            case .acquired(let lock):
                instanceLock = lock
            case .heldByAnotherCopy:
                // Opening here would let two copies overwrite each other's saves.
                Self.logger.error("Another copy of Dojix is using the data folder; opening nothing")
                isDatabaseFailed = true
                databaseError = Self.alreadyOpenMessage
                return
            case .unavailable:
                break
            }
        }
        let isLockOn: Bool
        do {
            isLockOn = try vault.legacyPasswordHash() != nil || vault.state() == .wrapped
        } catch {
            // Keychain unreadable: open nothing, change nothing, create no key.
            Self.logger.critical("Database key unavailable: \(error.localizedDescription)")
            isDatabaseFailed = true
            databaseError = Self.keychainUnavailableMessage
            return
        }
        isAppLockOn = isLockOn
        if isLockOn {
            isLocked = true
            encryptPlaintextLeftByOlderBuild()
        } else {
            openWithoutPassword()
        }
    }

    static let alreadyOpenMessage = "Dojix is already open. Switch to the copy that is running (or quit it and "
        + "reopen Dojix). This copy opened nothing, so your journal is safe."

    static let keychainUnavailableMessage = "Dojix can't read its database key from the Keychain, so your journal was left closed "
        + "and unchanged. Quit and reopen Dojix (if macOS asks, allow access to the Keychain)."

    /// App Lock set by an older build keeps the key as a bare Keychain item, and that
    /// build left the journal decrypted on disk while it ran (or after a crash). Encrypt
    /// it right away, before the lock screen is even shown. With a wrapped key there is
    /// never a plaintext journal to find.
    private func encryptPlaintextLeftByOlderBuild() {
        guard (try? vault.state()) != .wrapped else { return }
        let path = database.databasePath
        do {
            if DatabaseManager.isPlaintextFile(at: path) {
                let key = try vault.plainKey() ?? vault.createPlainKey()
                try DatabaseManager.encryptPlaintextFileInPlace(at: path, key: key)
            }
            if let key = try vault.plainKey() {
                DatabaseEncryption.sealStrayCopies(besides: path, key: key)
            }
        } catch {
            Self.logger.error("Could not encrypt the journal before unlock: \(error.localizedDescription)")
        }
    }

    /// App Lock off: the key is a bare Keychain item (created on first launch).
    private func openWithoutPassword() {
        do {
            let key: SymmetricKey
            if let existing = try vault.plainKey() {
                key = existing
            } else {
                // No key: a first launch, or the key was lost. Never decrypt-fail over an
                // encrypted journal with a new key: set that file aside first.
                if FileManager.default.fileExists(atPath: database.databasePath),
                   !DatabaseManager.isPlaintextFile(at: database.databasePath) {
                    let keptAs = moveAsideUnreadableDatabase()
                    databaseError = "Your journal's key is missing from the Keychain, so Dojix started a new, empty journal. "
                        + "The old file was kept as \(keptAs ?? "a copy") in \(dataFolderPath). "
                        + "You can restore a backup from Settings."
                }
                key = try vault.createPlainKey()
            }
            openJournal(with: key)
        } catch {
            Self.logger.critical("Database key unavailable: \(error.localizedDescription)")
            isDatabaseFailed = true
            databaseError = Self.keychainUnavailableMessage
        }
    }

    /// Decrypt the journal into memory. An unreadable file is set aside (never deleted)
    /// and a new, empty journal is started. A file older than the last one this Mac saved
    /// is neither opened nor moved: `olderJournal` is set so the user can decide, and
    /// false is returned. `allowOlderJournal` = the user already confirmed.
    @discardableResult
    func openJournal(with key: SymmetricKey, previousKey: SymmetricKey? = nil, allowOlderJournal: Bool = false) -> Bool {
        // Still loaded (an earlier save on lock failed): keep the unsaved data in memory.
        guard !database.isLoaded else { return true }
        do {
            try database.load(key: key, previousKey: previousKey, allowOlderJournal: allowOlderJournal)
        } catch let older as OlderJournalError {
            olderJournal = OlderJournalPrompt(error: older, needsPassword: isAppLockOn)
            return false
        } catch where !Self.isDamagedJournal(error) {
            // Not a damaged journal (a read error, a full disk, a permission problem):
            // never set a possibly healthy file aside; open nothing and change nothing.
            Self.logger.error("Journal file could not be read: \(error.localizedDescription)")
            isDatabaseFailed = true
            databaseError = "Dojix couldn't read your journal file (\(error.localizedDescription)). It was left unchanged "
                + "in \(dataFolderPath). Check the disk (free space, permissions), then quit and reopen Dojix."
            return false
        } catch {
            Self.logger.error("Database could not be opened: \(error.localizedDescription)")
            let keptAs = moveAsideUnreadableDatabase()
            do {
                try database.load(key: key)
                databaseError = "Your journal database could not be opened, so Dojix started a new, empty one. "
                    + "The old file was kept as \(keptAs ?? "a copy") in \(dataFolderPath). "
                    + "You can restore a backup from Settings."
            } catch {
                Self.logger.critical("Database unrecoverable: \(error.localizedDescription)")
                isDatabaseFailed = true
                databaseError = "Dojix cannot start due to a database error. Please restart the app."
                return false
            }
        }
        olderJournal = nil
        if let saveError = database.lastSaveError {
            databaseError = "Dojix opened your journal but couldn't save it (\(saveError)). Your journal on disk is "
                + "unchanged; free up disk space so your changes can be saved."
        }
        // Prop-firm settings older builds kept in UserDefaults move into the encrypted journal.
        do {
            try PropFirmSettings.migrateLegacyDefaults(into: SettingsRepository(database: database))
        } catch {
            Self.logger.error("Could not move prop firm settings into the journal: \(error.localizedDescription)")
        }
        // Screenshots saved by older builds are plain image files: encrypt them too.
        let screenshots = self.screenshots
        Task.detached(priority: .utility) {
            screenshots.encryptLegacyFiles()
        }
        return true
    }

    /// Whether opening failed because the file itself is damaged or not Dojix's (it
    /// doesn't decrypt with the key, or isn't a database): only then is it set aside.
    nonisolated static func isDamagedJournal(_ error: Error) -> Bool {
        if case DatabaseEncryption.EncryptionError.decryptionFailed? = error as? DatabaseEncryption.EncryptionError {
            return true
        }
        if let error = error as? DatabaseError {
            return [.SQLITE_NOTADB, .SQLITE_CORRUPT].contains(error.resultCode)
        }
        return false
    }

    // MARK: - Lock / unlock

    /// Check the password, unwrap the key and open the journal.
    /// `allowOlderJournal`: the user confirmed opening a journal older than the last save.
    /// A lock requested while this runs (lid closed, Cmd-H) is carried out when it ends,
    /// and "Erase Everything" waits for it.
    @MainActor
    func unlock(password: String, allowOlderJournal: Bool = false) async -> UnlockResult {
        // One unlock at a time (two windows): two at once could each migrate an older
        // build's lock to a different new key. (Allowed during a key change a lock
        // interrupted, so not refused on `keyOperationsInFlight`.)
        guard !isUnlocking else { return .failed(Self.alreadyUnlockingMessage) }
        isUnlocking = true
        beginKeyOperation()
        beginDeferringLocks()
        defer {
            endDeferringLocks()
            endKeyOperation()
            isUnlocking = false
        }
        let vault = self.vault
        let legacyHash: String?
        do {
            legacyHash = try vault.legacyPasswordHash()
            // A bare key (or none) and no lock hash: App Lock was never set, e.g. Enable
            // failed on a Keychain that couldn't be read and the lock was counted as on.
            // Open exactly as a relaunch would, instead of rejecting every password.
            if legacyHash == nil, try vault.state() != .wrapped {
                return openAsWithoutAppLock()
            }
        } catch {
            // Not "no lock": never take the no-password path (or count a wrong password).
            return .failed(error.localizedDescription)
        }
        let whileUnlocking = hooks.whileUnlocking
        let outcome: Result<DatabaseKeyVault.UnwrappedKeys, Error> = await Task.detached(priority: .userInitiated) {
            let keys = Result { try AppState.unlockKeys(vault: vault, password: password, legacyHash: legacyHash) }
            await whileUnlocking?()
            return keys
        }.value
        switch outcome {
        case .failure(DatabaseKeyVault.VaultError.wrongPassword):
            return .wrongPassword
        case .failure(let error):
            return .failed(error.localizedDescription)
        case .success(let keys):
            // The key is wrapped now; the old separate password hash is no longer needed.
            vault.removeLegacyPasswordHash()
            guard openJournal(with: keys.current, previousKey: keys.previous, allowOlderJournal: allowOlderJournal) else {
                return isDatabaseFailed ? .failed(databaseError ?? "The journal could not be opened.") : .olderJournal
            }
            if isDatabaseFailed { return .failed(databaseError ?? "The journal could not be opened.") }
            isAppLockOn = true
            if keys.previous != nil {
                // Finish a key rotation that was interrupted (or the migration just begun).
                let database = self.database
                let screenshots = self.screenshots
                do {
                    _ = try await Task.detached(priority: .userInitiated) {
                        try KeyRotation.finishAfterUnlock(keys: keys, password: password, vault: vault,
                                                          database: database, screenshots: screenshots)
                    }.value
                } catch {
                    // Both keys stay stored; the next unlock tries again. Nothing is lost.
                    // (Files that couldn't be re-sealed don't throw: they keep both keys too.)
                    Self.logger.error("Could not finish the key rotation: \(error.localizedDescription)")
                }
            }
            isLocked = false
            return .unlocked
        }
    }

    static let alreadyUnlockingMessage = "Dojix is already checking a password (maybe in another window). "
        + "Wait for it to finish."

    /// What a launch does with App Lock off: App Lock off, the journal opened with the
    /// bare key (or set aside if that key is missing), the lock screen gone.
    @MainActor
    private func openAsWithoutAppLock() -> UnlockResult {
        isAppLockOn = false
        openWithoutPassword()
        isLocked = false
        if isDatabaseFailed { return .failed(databaseError ?? "The journal could not be opened.") }
        return olderJournal == nil ? .unlocked : .olderJournal
    }

    /// The database key(s) for `password`. A lock set by an older build (bare key plus a
    /// password hash) is migrated here: after the hash checks out, a NEW key is created
    /// and stored wrapped (with the old one, until the journal is re-sealed) and the bare
    /// key is removed.
    nonisolated static func unlockKeys(vault: DatabaseKeyVault, password: String,
                                       legacyHash: String?) throws -> DatabaseKeyVault.UnwrappedKeys {
        switch try vault.state() {
        case .wrapped:
            let keys = try vault.unwrapKeys(password: password)
            vault.removePlainCopyIfWrapped()
            return keys
        case .plain, .empty:
            guard let legacyHash, PasswordHasher.verify(password, against: legacyHash) else {
                throw DatabaseKeyVault.VaultError.wrongPassword
            }
            let oldKey = try vault.plainKey() ?? vault.createPlainKey()
            let newKey = try vault.beginRotation(from: oldKey, password: password)
            return DatabaseKeyVault.UnwrappedKeys(current: newKey, previous: oldKey)
        }
    }

    /// Lock now (App Lock on): save, then wipe the decrypted journal from memory.
    /// Uses the lock state kept in memory (`isAppLockOn`), never a Keychain read of the
    /// moment, so a Keychain that is locked or slow can't keep the journal on screen.
    @MainActor
    func lock() {
        if lockDeferrals > 0 {
            // App Lock is being turned on, or an unlock is running: lock as soon as it ends.
            isLockRequestedMeanwhile = true
            return
        }
        guard !isLocked, !isDatabaseFailed, isAppLockOn else { return }
        stopFileWatcher()
        do {
            try database.unload()
        } catch {
            // Never discard unsaved data: it stays in memory behind the lock screen.
            Self.logger.error("Could not save before locking: \(error.localizedDescription)")
        }
        isLocked = true
        // Nothing presented on top of the journal (sheets, alerts, open/save panels) may
        // stay on screen over the lock screen; a cancelled panel exports nothing.
        LockCover.dismissModalUI()
    }

    /// Forgotten password: erase everything, then start a new, empty journal.
    /// Waits first for key operations still running (an unlock, a password change), so
    /// none of them can store its key over the new one afterwards.
    @MainActor
    func eraseAllAndStartFresh() async throws {
        await waitForKeyOperations()
        stopFileWatcher()
        try LocalDataEraser.eraseAll(database: database, screenshotsDirectory: screenshots.baseDir)
        vault.deleteKeys()   // already gone from the Keychain; also clears an injected store
        let key = try vault.createPlainKey()
        isAppLockOn = false
        openJournal(with: key)
        isLocked = false
    }

    /// "Quit & Relaunch" from the failure screen: let the new copy take the data folder
    /// right away (this copy is quitting). Kept while the journal is open, so two copies
    /// never hold it at once.
    @MainActor
    func releaseDataFolderForRelaunch() {
        guard !database.isLoaded else { return }
        instanceLock = nil
    }
}
