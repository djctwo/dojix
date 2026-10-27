import AppKit
import Foundation

/// What the "older journal" screen shows (see `OlderJournalError`).
struct OlderJournalPrompt: Equatable {
    /// When this Mac last saved the journal (the newer copy).
    let lastSavedAt: Date
    /// When the file on disk was saved; nil for a file from before save stamps existed.
    let fileSavedAt: Date?
    /// App Lock on: opening it anyway needs the App Lock password. Off: a confirmation.
    let needsPassword: Bool

    init(error: OlderJournalError, needsPassword: Bool) {
        lastSavedAt = error.lastSaved.savedAt
        fileSavedAt = error.fileStamp?.savedAt
        self.needsPassword = needsPassword
    }

    /// "This journal is older than the last one this Mac saved (saved <date>). Open it anyway?"
    var message: String {
        "This journal is older than the last one this Mac saved (saved "
            + "\(lastSavedAt.formatted(date: .abbreviated, time: .shortened))). Open it anyway?"
    }
}

/// Rollback protection: the user's decision about a journal file older than the last
/// one this Mac saved. Nothing is opened, moved or written until they choose.
extension AppState {
    /// Open the older journal anyway. With App Lock on, `password` must be the App Lock
    /// password (checked by unwrapping the key again); with it off, the call itself is
    /// the confirmation. The Keychain record is then reset to the file's generation.
    @MainActor
    func openOlderJournalAnyway(password: String?) async -> UnlockResult {
        guard let prompt = olderJournal else { return .unlocked }
        if prompt.needsPassword {
            guard let password, !password.isEmpty else { return .wrongPassword }
            let result = await unlock(password: password, allowOlderJournal: true)
            if result == .unlocked { olderJournal = nil }
            return result
        }
        do {
            guard let key = try vault.plainKey() else {
                return .failed(DatabaseEncryption.EncryptionError.keyUnavailable.localizedDescription)
            }
            openJournal(with: key, allowOlderJournal: true)
            return isDatabaseFailed ? .failed(databaseError ?? "The journal could not be opened.") : .unlocked
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Don't open it. With App Lock on, Dojix stays locked (the lock screen returns);
    /// with it off, Dojix quits, leaving the file untouched.
    @MainActor
    func keepOlderJournalClosed() {
        guard let prompt = olderJournal else { return }
        olderJournal = nil
        if !prompt.needsPassword {
            NSApplication.shared.terminate(nil)
        }
    }
}
