import SwiftUI

/// Full-screen lock gate — shown on launch when app lock is enabled
struct LockScreenView: View {
    @Environment(\.appState) private var appState
    @State private var password = ""
    @State private var error: String?
    @State private var showResetConfirmation = false
    @State private var isUnlocking = false
    @State private var isErasing = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.textSecondary)

            Text("Dojix is Locked")
                .font(.title2)
                .fontWeight(.bold)

            Text("Enter your password to unlock")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)

            VStack(spacing: 12) {
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .focused($isFocused)
                    .onSubmit { unlock() }
                    .disabled(isLockedOut)

                Button("Unlock") { unlock() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty || isLockedOut || isUnlocking || isErasing)

                if let error {
                    Text(error)
                        .font(.smallText)
                        .foregroundStyle(Color.semanticRed)
                }
            }

            Spacer()

            Button("Forgot Password?") {
                showResetConfirmation = true
            }
            // Never while a password is being checked: that unlock would carry on after
            // the erase (`eraseAllAndStartFresh` also waits for it).
            .disabled(isUnlocking || isErasing)
            .font(.smallText)
            .foregroundStyle(Color.textTertiary)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgContent)
        .preferredColorScheme(.dark)
        .onAppear {
            isFocused = true
            checkLockoutStatus()
        }
        .alert("Erase All Local Data?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Erase Everything", role: .destructive) {
                eraseAndStartFresh()
            }
        } message: {
            Text("Without the password, the only way back in is to start fresh. This permanently deletes every trade, note, tag and screenshot in Dojix, plus your saved API keys. Backups you exported are not affected and can be restored afterwards.")
        }
    }

    // MARK: - Brute Force Protection

    private var isLockedOut: Bool { UnlockThrottle.shared.isLockedOut }

    private func checkLockoutStatus() {
        if let message = UnlockThrottle.shared.lockoutMessage() {
            error = message
        }
    }

    // MARK: - Actions

    private func unlock() {
        guard !isLockedOut else {
            checkLockoutStatus()
            return
        }

        guard !isUnlocking, !isErasing else { return }
        isUnlocking = true
        let attempt = password
        Task { @MainActor in
            defer { isUnlocking = false }
            // The password unwraps the database key; only then is the journal decrypted.
            switch await appState.unlock(password: attempt) {
            case .unlocked:
                UnlockThrottle.shared.reset()
            case .olderJournal:
                // Right password; the "older journal" screen takes over.
                UnlockThrottle.shared.reset()
                password = ""
            case .wrongPassword:
                password = ""
                error = UnlockThrottle.shared.recordFailure()
            case .failed(let message):
                error = message
            }
        }
    }

    /// Forgotten password: erase all local data (never just remove the lock),
    /// then open the now-empty app. Requires the confirmation dialog.
    private func eraseAndStartFresh() {
        guard !isErasing else { return }
        isErasing = true
        Task { @MainActor in
            defer { isErasing = false }
            do {
                try await appState.eraseAllAndStartFresh()
                appState.showToast(.info, "All local data was erased. Restore a backup from Settings if you have one.")
            } catch {
                self.error = "Couldn't erase data: \(error.localizedDescription)"
            }
        }
    }
}
