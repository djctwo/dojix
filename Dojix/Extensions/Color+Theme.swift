import SwiftUI

extension Color {
    // MARK: - Backgrounds

    /// App window background — near-black warm (#0e0d0b)
    static let bgApp = Color(red: 0.055, green: 0.051, blue: 0.043)

    /// Sidebar background (#141310)
    static let bgSidebar = Color(red: 0.078, green: 0.075, blue: 0.063)

    /// Content area background (#111110)
    static let bgContent = Color(red: 0.067, green: 0.067, blue: 0.063)

    /// Card surface (#1c1b18)
    static let bgCard = Color(red: 0.110, green: 0.106, blue: 0.094)

    /// Card surface on hover (#232220)
    static let bgCardHover = Color(red: 0.137, green: 0.133, blue: 0.125)

    /// Inset/nested surface — warm tint at 3% opacity
    static let bgInset = Color(red: 1.0, green: 0.863, blue: 0.627, opacity: 0.03)

    // MARK: - Borders

    /// Card border — warm at 8% opacity
    static let borderCard = Color(red: 1.0, green: 0.863, blue: 0.627, opacity: 0.08)

    /// Subtle divider — warm at 6% opacity
    static let borderSubtle = Color(red: 1.0, green: 0.863, blue: 0.627, opacity: 0.06)

    /// Active/focused border — accent at 35% opacity
    static let borderActive = Color(red: 0.910, green: 0.706, blue: 0.298, opacity: 0.35)

    // MARK: - Accent

    /// Primary gold accent (#e8b44c)
    static let accent = Color(red: 0.910, green: 0.706, blue: 0.298)

    /// Accent at 14% opacity — for backgrounds of active items
    static let accentDim = Color(red: 0.910, green: 0.706, blue: 0.298, opacity: 0.14)

    /// Gradient end for accent (#d49a30)
    static let accentDark = Color(red: 0.831, green: 0.604, blue: 0.188)

    // MARK: - Text

    /// Primary text — warm off-white (#ece8df)
    static let textPrimary = Color(red: 0.925, green: 0.910, blue: 0.875)

    /// Secondary text — warm gray (#918d82)
    static let textSecondary = Color(red: 0.569, green: 0.553, blue: 0.510)

    /// Tertiary text — dim warm gray (#5e5b52)
    static let textTertiary = Color(red: 0.369, green: 0.357, blue: 0.322)

    // MARK: - Semantic Colors

    /// Profit / success green (#5cc98a)
    static let semanticGreen = Color(red: 0.361, green: 0.788, blue: 0.541)

    /// Loss / error red (#e06050)
    static let semanticRed = Color(red: 0.878, green: 0.376, blue: 0.314)

    /// Info / neutral blue (#6ba3d9)
    static let semanticBlue = Color(red: 0.420, green: 0.639, blue: 0.851)

    /// Purple for accents (#a48bd4)
    static let semanticPurple = Color(red: 0.643, green: 0.545, blue: 0.831)

    /// Amber — matches accent (#e8b44c)
    static let semanticAmber = Color(red: 0.910, green: 0.706, blue: 0.298)

    /// Cyan for secondary data (#4fb8c4)
    static let semanticCyan = Color(red: 0.310, green: 0.722, blue: 0.769)

    // MARK: - Semantic Dim Variants (badge/tag backgrounds)

    static let semanticGreenDim = Color(red: 0.361, green: 0.788, blue: 0.541, opacity: 0.14)
    static let semanticRedDim = Color(red: 0.878, green: 0.376, blue: 0.314, opacity: 0.14)
    static let semanticBlueDim = Color(red: 0.420, green: 0.639, blue: 0.851, opacity: 0.14)
    static let semanticPurpleDim = Color(red: 0.643, green: 0.545, blue: 0.831, opacity: 0.14)
    static let semanticAmberDim = Color(red: 0.910, green: 0.706, blue: 0.298, opacity: 0.14)
    static let semanticCyanDim = Color(red: 0.310, green: 0.722, blue: 0.769, opacity: 0.14)

    // MARK: - Pair-Specific Colors

    static let pairGBPUSD = semanticPurple
    static let pairAUDUSD = semanticAmber
    static let pairUSDJPY = semanticBlue
    static let pairEURUSD = semanticGreen
    static let pairGBPJPY = semanticRed

    // MARK: - Session Colors

    static let asianSession = semanticPurple
    static let londonSession = semanticBlue
    static let nyOverlapSession = semanticAmber
    static let nySession = semanticCyan
    static let lateSession = Color(red: 0.369, green: 0.357, blue: 0.322)

    // MARK: - Volatility Colors

    static let volLow = semanticBlue
    static let volMed = semanticAmber
    static let volHigh = semanticRed

    // MARK: - Legacy Aliases

    static let cardBackground = bgCard
    static let subtleBackground = bgApp
    static let cardBorder = borderCard
    static let mutedText = textSecondary
    static let sidebarBackground = bgSidebar
    static let profitGreen = semanticGreen
    static let lossRed = semanticRed
    static let breakeven = Color(white: 0.5)
    static let chartBlue = semanticBlue
    static let chartCyan = semanticCyan
    static let chartAmber = semanticAmber
    static let chartViolet = semanticPurple
    static let chartPink = Color(red: 1.0, green: 0.40, blue: 0.60)
    static let chartTeal = Color(red: 0.0, green: 0.70, blue: 0.65)

    // MARK: - Helpers

    /// Color for profit/loss values
    static func forPnL(_ value: Double) -> Color {
        if value > 0 { return .semanticGreen }
        if value < 0 { return .semanticRed }
        return .breakeven
    }

    /// Color for profit/loss Decimal values
    static func forPnL(_ value: Decimal) -> Color {
        forPnL(NSDecimalNumber(decimal: value).doubleValue)
    }

    /// Color for trading session
    static func forSession(_ session: TradingSession) -> Color {
        switch session {
        case .asian: .asianSession
        case .london: .londonSession
        case .nyOverlap: .nyOverlapSession
        case .ny: .nySession
        case .late: .lateSession
        }
    }

    /// Color for volatility regime
    static func forVolatility(_ regime: VolatilityRegime) -> Color {
        switch regime {
        case .low: .volLow
        case .med: .volMed
        case .high: .volHigh
        }
    }

    /// Color for currency pair symbol
    static func forPair(_ symbol: String) -> Color {
        switch symbol.uppercased() {
        case let s where s.contains("GBPUSD"): .pairGBPUSD
        case let s where s.contains("AUDUSD"): .pairAUDUSD
        case let s where s.contains("USDJPY"): .pairUSDJPY
        case let s where s.contains("EURUSD"): .pairEURUSD
        case let s where s.contains("GBPJPY"): .pairGBPJPY
        default: .textSecondary
        }
    }
}
