import SwiftUI

/// Reusable card displaying a single metric — warm gold trading terminal style
struct MetricCard: View {
    let title: String
    let value: String
    var subtitle: String?
    var valueColor: Color = .textPrimary
    var icon: String?
    /// Optional tooltip text shown on help button tap
    var tooltip: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textTertiary)
                }
                Text(title.uppercased())
                    .font(.kpiLabel)
                    .tracking(0.8)
                    .foregroundStyle(Color.textTertiary)

                if let tooltip {
                    HelpTooltip(term: title, definition: tooltip)
                }
            }

            Text(value)
                .font(.kpiValue)
                .tracking(-1)
                .foregroundStyle(valueColor)

            if let subtitle {
                Text(subtitle)
                    .font(.monoSubtitle)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.borderCard, lineWidth: 1)
        )
    }
}

/// Smaller variant for secondary KPI rows
struct MetricCardSmall: View {
    let title: String
    let value: String
    var subtitle: String?
    var valueColor: Color = .textPrimary
    var tooltip: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title.uppercased())
                    .font(.kpiLabel)
                    .tracking(0.8)
                    .foregroundStyle(Color.textTertiary)

                if let tooltip {
                    HelpTooltip(term: title, definition: tooltip)
                }
            }

            Text(value)
                .font(.kpiValueSecondary)
                .tracking(-0.5)
                .foregroundStyle(valueColor)

            if let subtitle {
                Text(subtitle)
                    .font(.monoSubtitle)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.borderCard, lineWidth: 1)
        )
    }
}

