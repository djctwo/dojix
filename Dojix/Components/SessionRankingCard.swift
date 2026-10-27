import SwiftUI

/// Session ranking card showing top sessions by P&L
struct SessionRankingCard: View {
    let trades: [Trade]

    private struct SessionRank: Identifiable {
        let id = UUID()
        let rank: Int
        let name: String
        let pnl: Double
        let trades: Int
        let winRate: Double
    }

    private var sessions: [SessionRank] {
        let grouped = Dictionary(grouping: trades) { $0.session }
        let ranked = TradingSession.allCases.compactMap { session -> (TradingSession, Double, Int, Double)? in
            let sessionTrades = grouped[session] ?? []
            guard !sessionTrades.isEmpty else { return nil }
            let pnl = sessionTrades.reduce(0.0) { $0 + $1.profitDouble }
            let wins = sessionTrades.filter(\.isWin).count
            let wr = Double(wins) / Double(sessionTrades.count) * 100
            return (session, pnl, sessionTrades.count, wr)
        }
        .sorted { $0.1 > $1.1 }

        return ranked.enumerated().map { index, data in
            SessionRank(
                rank: index + 1,
                name: data.0.displayName,
                pnl: data.1,
                trades: data.2,
                winRate: data.3
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.semanticAmberDim)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Image(systemName: "clock")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.accent)
                    )
                Text("Session Ranking")
                    .font(.cardTitle)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
            }

            // Session list
            if sessions.isEmpty {
                Text("No trades yet")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                        HStack(spacing: 12) {
                            // Rank badge
                            RoundedRectangle(cornerRadius: 6)
                                .fill(session.rank == 1 ? Color.semanticAmberDim : Color(red: 1.0, green: 0.863, blue: 0.627, opacity: 0.05))
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Text("\(session.rank)")
                                        .font(.custom("JetBrains Mono", size: 14).weight(.bold))
                                        .foregroundStyle(session.rank == 1 ? Color.accent : Color.textTertiary)
                                )

                            // Session name
                            Text(session.name)
                                .font(.custom("DM Sans", size: 16).weight(.semibold))
                                .foregroundStyle(Color.textPrimary)

                            Spacer()

                            // Stats
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(session.pnl.asCurrency)
                                    .font(.custom("JetBrains Mono", size: 16).weight(.semibold))
                                    .foregroundStyle(Color.forPnL(session.pnl))

                                Text("\(session.trades)t · \(String(format: "%.1f", session.winRate))%")
                                    .font(.custom("JetBrains Mono", size: 14))
                                    .foregroundStyle(Color.textTertiary)
                            }
                        }
                        .padding(.vertical, 10)

                        if index < sessions.count - 1 {
                            Rectangle()
                                .fill(Color.borderSubtle)
                                .frame(height: 1)
                        }
                    }
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
