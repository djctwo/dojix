import SwiftUI

// MARK: - Card Style

/// Standard card surface: warm background, 12px radius, 1px warm border, hover effect
struct CardStyleModifier: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(isHovered ? Color.bgCardHover : Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.borderCard, lineWidth: 1)
            )
            .onHover { isHovered = $0 }
    }
}

// MARK: - Inset Surface

/// Nested surface inside cards: warm tint background, 8px radius
struct InsetSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.bgInset)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.04), lineWidth: 1)
            )
    }
}

// MARK: - KPI Glow

/// Subtle colored glow effect for KPI cards — blurred circle at top-right
struct KPIGlowModifier: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(color)
                    .frame(width: 80, height: 80)
                    .blur(radius: 30)
                    .opacity(0.12)
                    .offset(x: 20, y: -20)
            }
            .clipped()
    }
}

// MARK: - Accent Top Bar

/// Gold gradient bar along top edge of a card
struct AccentTopBarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [Color.accent, Color.accentDark],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 2)
            }
    }
}

// MARK: - View Extensions

extension View {
    /// Apply standard warm gold card styling
    func cardStyle() -> some View {
        modifier(CardStyleModifier())
    }

    /// Apply inset surface styling (for nested containers within cards)
    func insetSurface() -> some View {
        modifier(InsetSurfaceModifier())
    }

    /// Add a subtle KPI glow effect
    func kpiGlow(_ color: Color) -> some View {
        modifier(KPIGlowModifier(color: color))
    }

    /// Add a gold gradient accent bar along the top edge
    func accentTopBar() -> some View {
        modifier(AccentTopBarModifier())
    }
}
