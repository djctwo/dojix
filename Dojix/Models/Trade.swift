import Foundation
import GRDB

/// Represents a single trade imported from StrategyAnalytics CSV
struct Trade: Codable, Identifiable, Sendable {
    // MARK: - Core Fields

    var id: Int64?
    var ticket: Int64
    var symbol: String
    var direction: TradeDirection
    var lots: Double
    var openTime: Date
    var closeTime: Date
    var durationMin: Int
    var openPrice: Decimal
    var closePrice: Decimal
    var sl: Decimal
    var tp: Decimal
    var netProfit: Decimal

    // MARK: - SA Computed Metrics

    var maePips: Double
    var mfePips: Double
    var rMultiple: Double
    var session: TradingSession
    var dayOfWeek: String
    var hour: Int
    var rangeSize: Double
    var sweepDepth: Double
    var usedFVG: Bool
    var volRegime: VolatilityRegime
    var hitBreakeven: Bool
    var scaledIn: Bool
    var magic: Int
    var comment: String

    // MARK: - Advanced Metrics (Mar 2026)

    var timeToMFEMin: Int
    var slDistPips: Double
    var slippagePips: Double
    var postClose15m: Double
    var postClose30m: Double
    var biasAtEntry: BiasAlignment

    // MARK: - User Annotations

    var notes: String = ""
    var tags: String = ""  // Comma-separated tags
    var emotion: String = ""  // Pre-trade emotional state
    var screenshots: String = ""  // Comma-separated filenames
    var checklistData: String = ""  // JSON: {"rule": true/false}

    // MARK: - Costs

    var commission: Decimal = 0  // Trading commission
    var swap: Decimal = 0  // Overnight swap fee

    // MARK: - Import Metadata

    var importedAt: Date
}

// MARK: - Enums

enum TradeDirection: String, Codable, DatabaseValueConvertible, Sendable {
    case buy = "BUY"
    case sell = "SELL"
}

extension TradeDirection: Comparable {
    static func < (lhs: TradeDirection, rhs: TradeDirection) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum TradingSession: String, Codable, DatabaseValueConvertible, CaseIterable, Sendable {
    case asian = "ASIAN"
    case london = "LONDON"
    case nyOverlap = "NY_OVERLAP"
    case ny = "NY"
    case late = "LATE"

    var displayName: String {
        switch self {
        case .asian: "Asian"
        case .london: "London"
        case .nyOverlap: "NY Overlap"
        case .ny: "New York"
        case .late: "Late"
        }
    }

    /// Sessions whose tagged trades are relevant to this session's analysis.
    /// London includes nyOverlap trades (12-16 UTC is still London hours).
    /// NY includes nyOverlap trades (12-16 UTC is also NY hours).
    var relatedSessions: Set<TradingSession> {
        switch self {
        case .london: [.london, .nyOverlap]
        case .ny: [.ny, .nyOverlap]
        default: [self]
        }
    }

    /// Session end hour in UTC
    var endHourUTC: Int {
        switch self {
        case .asian: 9
        case .london: 16
        case .nyOverlap: 16
        case .ny: 21
        case .late: 24
        }
    }

    /// Session start hour in UTC
    var startHourUTC: Int {
        switch self {
        case .asian: 0
        case .london: 7
        case .nyOverlap: 12
        case .ny: 12
        case .late: 21
        }
    }
}

extension TradingSession: Comparable {
    static func < (lhs: TradingSession, rhs: TradingSession) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum VolatilityRegime: String, Codable, DatabaseValueConvertible, CaseIterable, Sendable {
    case low = "LOW"
    case med = "MED"
    case high = "HIGH"
}

enum BiasAlignment: String, Codable, DatabaseValueConvertible, Sendable {
    case with = "WITH"
    case against = "AGAINST"
    case neutral = "NEUTRAL"
}

/// Pre-trade emotional state for tiltmeter tracking
enum TradeEmotion: String, Codable, CaseIterable, Sendable {
    case calm = "CALM"
    case confident = "CONFIDENT"
    case anxious = "ANXIOUS"
    case frustrated = "FRUSTRATED"
    case revenge = "REVENGE"
    case fomo = "FOMO"
    case bored = "BORED"

    var displayName: String {
        switch self {
        case .calm: "Calm"
        case .confident: "Confident"
        case .anxious: "Anxious"
        case .frustrated: "Frustrated"
        case .revenge: "Revenge"
        case .fomo: "FOMO"
        case .bored: "Bored"
        }
    }

    var icon: String {
        switch self {
        case .calm: "leaf.fill"
        case .confident: "bolt.fill"
        case .anxious: "exclamationmark.triangle.fill"
        case .frustrated: "flame.fill"
        case .revenge: "arrow.counterclockwise"
        case .fomo: "clock.badge.exclamationmark.fill"
        case .bored: "zzz"
        }
    }

    var color: String {
        switch self {
        case .calm: "green"
        case .confident: "blue"
        case .anxious: "yellow"
        case .frustrated: "orange"
        case .revenge: "red"
        case .fomo: "purple"
        case .bored: "gray"
        }
    }
}

// MARK: - GRDB Record Conformance

extension Trade: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "trades"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Computed Properties

extension Trade {
    var isWin: Bool { netProfit > 0 }
    var isLoss: Bool { netProfit < 0 }
    var profitDouble: Double { NSDecimalNumber(decimal: netProfit).doubleValue }

    var directionSymbol: String {
        direction == .buy ? "↑" : "↓"
    }

    var pairDisplay: String {
        let base = String(symbol.prefix(3))
        let quote = String(symbol.suffix(3))
        return "\(base)/\(quote)"
    }

    /// Parsed tags from comma-separated string
    var tagList: [String] {
        tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Add a tag
    func withTag(_ tag: String) -> Trade {
        var copy = self
        var existing = copy.tagList
        if !existing.contains(tag) {
            existing.append(tag)
            copy.tags = existing.joined(separator: ",")
        }
        return copy
    }

    /// Remove a tag
    func withoutTag(_ tag: String) -> Trade {
        var copy = self
        copy.tags = copy.tagList.filter { $0 != tag }.joined(separator: ",")
        return copy
    }

    /// Parsed emotion from stored string
    var tradeEmotion: TradeEmotion? {
        guard !emotion.isEmpty else { return nil }
        return TradeEmotion(rawValue: emotion)
    }

    /// Net P&L after commissions and swap
    var netProfitAfterCosts: Decimal {
        netProfit - commission - swap
    }

    /// Net P&L after costs as Double
    var profitAfterCostsDouble: Double {
        NSDecimalNumber(decimal: netProfitAfterCosts).doubleValue
    }

    /// Commission as Double
    var commissionDouble: Double {
        NSDecimalNumber(decimal: commission).doubleValue
    }

    /// Swap as Double
    var swapDouble: Double {
        NSDecimalNumber(decimal: swap).doubleValue
    }

    /// Total costs (commission + swap)
    var totalCosts: Double {
        commissionDouble + swapDouble
    }

    /// Parsed screenshot filenames
    var screenshotList: [String] {
        screenshots.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Parsed checklist compliance data
    var checklistResults: [String: Bool] {
        guard !checklistData.isEmpty,
              let data = checklistData.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: Bool].self, from: data) else {
            return [:]
        }
        return dict
    }

    /// Base currency from symbol (first 3 characters, e.g., "GBP" from "GBPUSD")
    var baseCurrency: String {
        String(symbol.prefix(3))
    }

    /// Quote currency from symbol (last 3 characters, e.g., "USD" from "GBPUSD")
    var quoteCurrency: String {
        String(symbol.suffix(3))
    }

    /// Exit efficiency: how much of MFE was captured (0-100%)
    var exitEfficiency: Double? {
        guard mfePips > 0, slDistPips > 0 else { return nil }
        let capturedPips = rMultiple * slDistPips
        return min(max(capturedPips / mfePips * 100, 0), 100)
    }

    /// Money left on table: MFE minus actual profit in pips
    var moneyLeftOnTable: Double? {
        guard mfePips > 0, isWin else { return nil }
        let capturedPips = rMultiple * slDistPips
        return max(mfePips - capturedPips, 0)
    }
}
