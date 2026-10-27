import SwiftUI

/// A collapsible section with header, chevron, and animated content reveal.
/// Remembers expanded/collapsed state in UserDefaults per section key.
struct CollapsibleSection<Content: View>: View {
    let title: String
    let icon: String
    let storageKey: String
    @ViewBuilder let content: () -> Content

    @State private var isExpanded: Bool

    init(
        title: String,
        icon: String,
        storageKey: String,
        defaultExpanded: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.storageKey = storageKey
        self.content = content
        // Restore saved state, defaulting to collapsed
        self._isExpanded = State(initialValue: UserDefaults.standard.object(forKey: storageKey) as? Bool ?? defaultExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header — always visible
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                    UserDefaults.standard.set(isExpanded, forKey: storageKey)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.accent)
                        .frame(width: 20)

                    Text(title.uppercased())
                        .font(.sectionLabel)
                        .tracking(1.2)
                        .foregroundStyle(Color.textSecondary)

                    Spacer()

                    Text(isExpanded ? "Collapse" : "Expand")
                        .font(.smallText)
                        .foregroundStyle(Color.textTertiary)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Collapsible content
            if isExpanded {
                VStack(spacing: 16) {
                    content()
                }
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
