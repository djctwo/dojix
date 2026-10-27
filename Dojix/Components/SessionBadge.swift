import SwiftUI

/// Badge showing a trading session with colored background
struct SessionBadge: View {
    let session: TradingSession

    var body: some View {
        Text(session.displayName)
            .font(.smallText)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.forSession(session).opacity(0.2))
            .foregroundStyle(Color.forSession(session))
            .clipShape(Capsule())
    }
}

/// Badge showing volatility regime
struct VolatilityBadge: View {
    let regime: VolatilityRegime

    var body: some View {
        Text(regime.rawValue)
            .font(.smallText)
            .fontWeight(.bold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.forVolatility(regime).opacity(0.2))
            .foregroundStyle(Color.forVolatility(regime))
            .clipShape(Capsule())
    }
}

/// Badge showing bias alignment
struct BiasBadge: View {
    let bias: BiasAlignment

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: iconName)
                .font(.caption)
            Text(bias.rawValue)
                .font(.smallText)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(biasColor.opacity(0.15))
        .foregroundStyle(biasColor)
        .clipShape(Capsule())
    }

    private var iconName: String {
        switch bias {
        case .with: "checkmark.circle.fill"
        case .against: "xmark.circle.fill"
        case .neutral: "minus.circle.fill"
        }
    }

    private var biasColor: Color {
        switch bias {
        case .with: .semanticGreen
        case .against: .semanticRed
        case .neutral: .secondary
        }
    }
}
