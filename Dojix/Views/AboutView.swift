import SwiftUI

/// Custom About Dojix window
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    var body: some View {
        VStack(spacing: 20) {
            // App Icon
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            // Title + Version
            VStack(spacing: 4) {
                Text("Dojix")
                    .font(.title)
                    .fontWeight(.bold)
                Text("Trade Journaling & Edge Detection")
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
                Text("Version \(appVersion) (\(buildNumber))")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
            }

            Divider()
                .frame(width: 200)

            // Keyboard shortcuts
            VStack(alignment: .leading, spacing: 6) {
                Text("Keyboard Shortcuts")
                    .font(.smallText)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.textSecondary)

                shortcutRow("Journal", "Cmd+1")
                shortcutRow("Dashboard", "Cmd+2")
                shortcutRow("Analytics", "Cmd+3")
                shortcutRow("Edge Report", "Cmd+4")
                shortcutRow("Pulse", "Cmd+5")
                shortcutRow("Import", "Cmd+6")
                shortcutRow("Settings", "Cmd+,")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)

            Divider()
                .frame(width: 200)

            // Copyright
            VStack(spacing: 2) {
                Text("\u{00A9} 2026 Douglas Cleary")
                Text("Free software under the GNU GPL v3")
            }
            .font(.smallText)
            .foregroundStyle(Color.textTertiary)

            Spacer()
        }
        .padding(24)
        .frame(width: 320, height: 440)
    }

    private func shortcutRow(_ label: String, _ shortcut: String) -> some View {
        HStack {
            Text(label)
                .font(.smallText)
            Spacer()
            Text(shortcut)
                .font(.monoSubtitle)
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
       .overlay(
           RoundedRectangle(cornerRadius: 12)
               .stroke(Color.borderCard, lineWidth: 1)
       )
        }
    }
}
