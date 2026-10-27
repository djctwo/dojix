import SwiftUI

/// Toast notification type
enum ToastStyle {
    case success
    case error
    case info

    var icon: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .error: "xmark.circle.fill"
        case .info: "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .success: .semanticGreen
        case .error: .semanticRed
        case .info: .accent
        }
    }
}

/// Toast notification data
struct ToastData: Equatable {
    let style: ToastStyle
    let message: String

    static func == (lhs: ToastData, rhs: ToastData) -> Bool {
        lhs.message == rhs.message
    }
}

/// Toast notification overlay view
struct ToastView: View {
    let toast: ToastData
    @Binding var isPresented: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.style.icon)
                .foregroundStyle(toast.style.color)
            Text(toast.message)
                .font(.smallText)
            Spacer()
            Button {
                withAnimation { isPresented = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.borderCard, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .transition(.move(edge: .top).combined(with: .opacity))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                withAnimation { isPresented = false }
            }
        }
    }
}

/// ViewModifier for showing toast notifications
struct ToastModifier: ViewModifier {
    @Binding var toast: ToastData?

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let toast {
                ToastView(toast: toast, isPresented: .init(
                    get: { self.toast != nil },
                    set: { if !$0 { self.toast = nil } }
                ))
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
        .animation(.spring(duration: 0.3), value: toast)
    }
}

extension View {
    func toast(_ toast: Binding<ToastData?>) -> some View {
        modifier(ToastModifier(toast: toast))
    }
}
