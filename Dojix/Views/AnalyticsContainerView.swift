import SwiftUI

/// Container view that wraps DashboardView with horizontal pill sub-navigation
/// for analytics categories (Timing, Sessions, Pairs, Risk, Behavioral, Advanced)
struct AnalyticsContainerView: View {
    @Bindable var viewModel: DashboardViewModel
    @Environment(\.appState) private var appState
    @State private var selectedCategory: DashboardViewModel.DashboardCategory = .timing

    /// Analytics-only categories (excludes overview, all, propFirm)
    private let categories: [DashboardViewModel.DashboardCategory] = [
        .timing, .sessions, .pairs, .risk, .behavioral, .advanced
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Pill tab bar
            pillTabBar
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 4)

            // Content
            DashboardView(viewModel: viewModel, category: selectedCategory)
        }
        .navigationTitle("Analytics")
    }

    // MARK: - Pill Tab Bar

    private var pillTabBar: some View {
        HStack(spacing: 6) {
            ForEach(categories) { category in
                pillTab(category)
            }
            Spacer()
        }
    }

    private func pillTab(_ category: DashboardViewModel.DashboardCategory) -> some View {
        let isSelected = selectedCategory == category

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedCategory = category
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: category.icon)
                    .font(.system(size: 11))
                Text(category.rawValue)
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? Color.bgApp : Color.textSecondary)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accent : Color.bgCard)
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : Color.borderCard, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
