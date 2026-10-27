import SwiftUI

/// Streak card showing current win/loss streak with recent results
struct StreakCard: View {
    let trades: [Trade]

    private var sortedTrades: [Trade] {
        trades.sorted { $0.closeTime < $1.closeTime }
    }

    private var currentStreak: Int {
        guard let last = sortedTrades.last else { return 0 }
        let isWin = last.isWin
        var count = 0
        for trade in sortedTrades.reversed() {
            if trade.isWin == isWin {
                count += 1
            } else {
                break
            }
        }
        return isWin ? count : -count
    }

    private var bestWinStreak: Int {
        var best = 0
        var current = 0
        for trade in sortedTrades {
            if trade.isWin {
                current += 1
                best = max(best, current)
            } else {
                current = 0
            }
        }
        return best
    }

    private var bestLossStreak: Int {
        var best = 0
        var current = 0
        for trade in sortedTrades {
            if trade.isLoss {
                current += 1
                best = max(best, current)
            } else {
                current = 0
            }
        }
        return best
    }

    /// Last 10 trade results (most recent last)
    private var recentResults: [Bool] {
        sortedTrades.suffix(10).map(\.isWin)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.semanticGreenDim)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.semanticGreen)
                    )
                Text("Streak")
                    .font(.cardTitle)
                    .foregroundStyle(Color.textPrimary)
                Spacer()

                // Streak badge
                if !trades.isEmpty {
                    let streakText = currentStreak >= 0 ? "+\(currentStreak)" : "\(currentStreak)"
                    let streakColor = currentStreak >= 0 ? Color.semanticGreen : Color.semanticRed
                    let streakBg = currentStreak >= 0 ? Color.semanticGreenDim : Color.semanticRedDim
                    Text(streakText)
                        .font(.custom("JetBrains Mono", size: 14).weight(.semibold))
                        .foregroundStyle(streakColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(streakBg)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            if trades.isEmpty {
                Text("No trades yet")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                // Big streak number
                VStack(spacing: 8) {
                    Text(currentStreak >= 0 ? "+\(currentStreak)" : "\(currentStreak)")
                        .font(.custom("JetBrains Mono", size: 48).weight(.bold))
                        .foregroundStyle(currentStreak >= 0 ? Color.semanticGreen : Color.semanticRed)

                    Text("Best: \(bestWinStreak)W / \(bestLossStreak)L")
                        .font(.custom("DM Sans", size: 15))
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)

                // Win/loss timeline squares
                HStack(spacing: 3) {
                    Spacer()
                    ForEach(Array(recentResults.enumerated()), id: \.offset) { _, isWin in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isWin ? Color.semanticGreenDim : Color.semanticRedDim)
                            .frame(width: 18, height: 18)
                    }
                    Spacer()
                }
            }
        }
        .padding(20)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.borderCard, lineWidth: 1)
        )
    }
}
