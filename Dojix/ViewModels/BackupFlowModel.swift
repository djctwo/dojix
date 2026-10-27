import AppKit
import Foundation
import UniformTypeIdentifiers

/// "Export Backup" and "Restore Backup" in Settings: the password option, the file
/// panels, and the password prompt for protected backups. The work itself is
/// `BackupService` (validation, rebuild) and `BackupEncryption` (format).
@Observable
@MainActor
final class BackupFlowModel {
    // MARK: Export sheet
    var showExportSheet = false
    var protectWithPassword = false
    var password = ""
    var confirmPassword = ""
    var exportError: String?

    // MARK: Restore password sheet
    var showRestorePasswordSheet = false
    var restorePassword = ""
    var restoreError: String?
    private(set) var pendingRestore: URL?

    var isWorking = false

    /// Outcome shown as a toast by the view.
    enum Outcome: Equatable {
        case none
        case success(String)
        case failure(String)
    }

    // MARK: - Export

    /// Open the export sheet. Password protection starts on when App Lock is on.
    func beginExport(isAppLockOn: Bool) {
        protectWithPassword = isAppLockOn
        password = ""
        confirmPassword = ""
        exportError = nil
        showExportSheet = true
    }

    /// Check the password (if any), ask where to save, then write the backup.
    func export(from database: DatabaseManager) async -> Outcome {
        let backupPassword: String?
        if protectWithPassword {
            if let problem = PasswordRules.problem(password: password, confirmation: confirmPassword) {
                exportError = problem
                return .none
            }
            backupPassword = password
        } else {
            backupPassword = nil
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "dojix") ?? .data]
        panel.nameFieldStringValue = "Dojix_Backup_\(Date().formatted(.dateTime.year().month().day())).dojix"
        panel.message = backupPassword == nil
            ? "Choose where to save your backup (not encrypted: anyone with the file can read it)"
            : "Choose where to save your password-protected backup"
        guard panel.runModal() == .OK, let destination = panel.url else { return .none }

        isWorking = true
        defer { isWorking = false }
        do {
            try await Task.detached(priority: .userInitiated) {
                try BackupService.writeBackup(of: database, to: destination, password: backupPassword)
            }.value
            clearPasswords()
            showExportSheet = false
            let kind = backupPassword == nil ? "Backup" : "Password-protected backup"
            return .success("\(kind) saved as \(destination.lastPathComponent)")
        } catch {
            exportError = error.friendlyMessage
            return .none
        }
    }

    // MARK: - Restore

    /// Ask for a backup file. A plain one is restored at once; a password-protected one
    /// opens the password sheet first.
    func beginRestore(into database: DatabaseManager) async -> Outcome {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["dojix", "dojix-enc"].map { UTType(filenameExtension: $0) ?? .data }
        panel.message = "Select a Dojix backup file to restore"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let source = panel.url else { return .none }

        if BackupEncryption.kind(ofFileAt: source).needsPassword {
            pendingRestore = source
            restorePassword = ""
            restoreError = nil
            showRestorePasswordSheet = true
            return .none
        }
        return await restore(source, password: nil, into: database)
    }

    /// Restore the pending protected backup with the password typed in the sheet. A
    /// wrong password keeps the sheet open with a clear message; the journal is untouched.
    func restoreWithPassword(into database: DatabaseManager) async -> Outcome {
        guard let source = pendingRestore else { return .none }
        guard !restorePassword.isEmpty else {
            restoreError = BackupService.BackupError.passwordRequired.localizedDescription
            return .none
        }
        return await restore(source, password: restorePassword, into: database)
    }

    func cancelRestore() {
        pendingRestore = nil
        restorePassword = ""
        restoreError = nil
        showRestorePasswordSheet = false
    }

    private func restore(_ source: URL, password: String?, into database: DatabaseManager) async -> Outcome {
        isWorking = true
        defer { isWorking = false }
        do {
            let summary = try await Task.detached(priority: .userInitiated) {
                try BackupService.restore(from: source, password: password, into: database)
            }.value
            cancelRestore()
            return .success("Backup restored (\(summary.trades) trades)")
        } catch BackupService.BackupError.wrongPassword where password != nil {
            restorePassword = ""
            restoreError = BackupService.BackupError.wrongPassword.localizedDescription
            return .none
        } catch {
            cancelRestore()
            return .failure(error.friendlyMessage)
        }
    }

    private func clearPasswords() {
        password = ""
        confirmPassword = ""
        exportError = nil
    }
}
