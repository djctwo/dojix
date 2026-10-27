import SwiftUI

/// Rollback protection: shown instead of the journal when the journal file is older than
/// the last one this Mac saved. Nothing has been opened or changed yet.
struct OlderJournalView: View {
    @Environment(\.appState) private var appState
    let prompt: OlderJournalPrompt
    @State private var password = ""
    @State private var error: String?
    @State private var isOpening = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 44))
                .foregroundStyle(Color.semanticRed)

            Text("Older Journal Found")
                .font(.title2)
                .fontWeight(.bold)

            Text(prompt.message)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            Text(detail)
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            if prompt.needsPassword {
                SecureField("App Lock Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .focused($isFocused)
                    .onSubmit { openAnyway() }
            }

            if let error {
                Text(error)
                    .font(.smallText)
                    .foregroundStyle(Color.semanticRed)
            }

            HStack(spacing: 12) {
                Button(prompt.needsPassword ? "Cancel" : "Quit Dojix") {
                    appState.keepOlderJournalClosed()
                }
                .keyboardShortcut(.cancelAction)

                Button("Open Anyway", role: .destructive) { openAnyway() }
                    .disabled(isOpening || (prompt.needsPassword && password.isEmpty))
            }

            Spacer()
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgContent)
        .preferredColorScheme(.dark)
        .onAppear {
            isFocused = true
            if let message = UnlockThrottle.shared.lockoutMessage() { error = message }
        }
    }

    private var detail: String {
        var text = "Someone or something may have replaced Dojix's journal file with an older copy, "
            + "which would bring back old data and lose newer changes."
        if let fileSavedAt = prompt.fileSavedAt {
            text += " The file found was saved \(fileSavedAt.formatted(date: .abbreviated, time: .shortened))."
        }
        text += prompt.needsPassword
            ? " If you didn't put an older copy back yourself, choose Cancel. To open it anyway, enter your App Lock password."
            : " If you didn't put an older copy back yourself, quit Dojix and check the file."
        return text
    }

    private func openAnyway() {
        guard !isOpening else { return }
        if prompt.needsPassword, let message = UnlockThrottle.shared.lockoutMessage() {
            error = message
            return
        }
        isOpening = true
        let attempt = password
        Task { @MainActor in
            defer { isOpening = false }
            switch await appState.openOlderJournalAnyway(password: prompt.needsPassword ? attempt : nil) {
            case .unlocked:
                if prompt.needsPassword { UnlockThrottle.shared.reset() }
            case .wrongPassword:
                password = ""
                error = UnlockThrottle.shared.recordFailure()
            case .failed(let message):
                error = message
            case .olderJournal:
                error = "The journal could not be opened."
            }
        }
    }
}
