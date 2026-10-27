import SwiftUI

/// Shown when the database cannot be initialized even after recovery.
/// Replaces the previous fatalError() crash with a user-friendly screen.
struct DatabaseFailedView: View {
    let errorMessage: String
    @Environment(\.appState) private var appState

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.semanticRed)

            Text("Database Error")
                .font(.title2)
                .fontWeight(.bold)

            Text(errorMessage)
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            VStack(spacing: 12) {
                Button("Quit & Relaunch") {
                    // Free the data folder first: the new copy may check it before this
                    // one has quit, and would otherwise say "Dojix is already open".
                    appState.releaseDataFolderForRelaunch()
                    let url = Bundle.main.bundleURL
                    let config = NSWorkspace.OpenConfiguration()
                    config.createsNewApplicationInstance = true
                    NSWorkspace.shared.openApplication(at: url, configuration: config)
                    NSApp.terminate(nil)
                }
                .buttonStyle(.borderedProminent)

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgContent)
        .preferredColorScheme(.dark)
    }
}
