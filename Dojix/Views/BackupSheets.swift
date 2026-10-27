import SwiftUI

/// "Export Backup": optional password protection, then a save panel.
struct BackupExportSheet: View {
    @Bindable var flow: BackupFlowModel
    let onExport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export Backup")
                .font(.headline)

            Toggle("Protect this backup with a password", isOn: $flow.protectWithPassword)
                .accessibilityIdentifier("protectBackupToggle")

            if flow.protectWithPassword {
                VStack(spacing: 10) {
                    SecureField("Backup Password", text: $flow.password)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Confirm Backup Password", text: $flow.confirmPassword)
                        .textFieldStyle(.roundedBorder)
                }
                Text("Minimum 8 characters. Encrypted with AES-256-GCM using a key derived from this password "
                     + "(PBKDF2-SHA256, 600,000 iterations). There is no way to recover a forgotten backup password.")
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
            } else {
                Text("Without a password the backup is not encrypted: anyone who gets the file can read every "
                     + "trade and note in it. Protecting it with a password is recommended.")
                    .font(.smallText)
                    .foregroundStyle(Color.semanticRed)
            }

            if let error = flow.exportError {
                Text(error)
                    .font(.smallText)
                    .foregroundStyle(Color.semanticRed)
            }

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") { flow.showExportSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button("Choose Location…") { onExport() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(flow.isWorking
                              || (flow.protectWithPassword && (flow.password.isEmpty || flow.confirmPassword.isEmpty)))
            }
        }
        .padding(24)
        .frame(width: 400)
        .onChange(of: flow.password) { limit(\.password) }
        .onChange(of: flow.confirmPassword) { limit(\.confirmPassword) }
    }

    private func limit(_ field: ReferenceWritableKeyPath<BackupFlowModel, String>) {
        if flow[keyPath: field].count > PasswordRules.maximumLength {
            flow[keyPath: field] = String(flow[keyPath: field].prefix(PasswordRules.maximumLength))
        }
    }
}

/// Password prompt for restoring a password-protected backup.
struct BackupRestorePasswordSheet: View {
    @Bindable var flow: BackupFlowModel
    let onRestore: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Password-Protected Backup")
                .font(.headline)

            Text("Enter the password this backup was saved with. Restoring replaces the trades in your journal.")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)

            SecureField("Backup Password", text: $flow.restorePassword)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                .onSubmit { onRestore() }

            if let error = flow.restoreError {
                Text(error)
                    .font(.smallText)
                    .foregroundStyle(Color.semanticRed)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                Button("Cancel") { flow.cancelRestore() }
                    .keyboardShortcut(.cancelAction)
                Button("Restore") { onRestore() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(flow.restorePassword.isEmpty || flow.isWorking)
            }
            if flow.isWorking {
                ProgressView().controlSize(.small)
            }
        }
        .padding(30)
        .frame(width: 380)
    }
}
