import SwiftUI

/// Styled currency pair label with pair-specific colors
struct PairLabel: View {
    let symbol: String

    var body: some View {
        Text(displayPair)
            .font(.system(.body, design: .monospaced))
            .fontWeight(.bold)
            .foregroundStyle(Color.forPair(symbol))
    }

    private var displayPair: String {
        guard symbol.count == 6 else { return symbol }
        let base = String(symbol.prefix(3))
        let quote = String(symbol.suffix(3))
        return "\(base)/\(quote)"
    }
}

/// Direction pill badge with colored background
struct DirectionLabel: View {
    let direction: TradeDirection

    var body: some View {
        Text(direction.rawValue)
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(direction == .buy ? Color.semanticGreenDim : Color.semanticRedDim)
            .foregroundStyle(direction == .buy ? Color.semanticGreen : Color.semanticRed)
            .clipShape(Capsule())
    }
}
