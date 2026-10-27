import SwiftUI

struct SidebarView: View {
    @Binding var selectedTab: SidebarTab
    @Environment(\.appState) private var appState
    @State private var currentTime = Date()
    @State private var toolsExpanded = true
    @State private var hoveredTab: SidebarTab?
    @State private var dotGlowExpanded = false
    @State private var quotesLastUpdated: Date?
    @State private var lastQuoteSnapshot = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            // Logo
            logoHeader
                .padding(.top, 12)
                .padding(.bottom, 8)

            // Navigation
            ScrollView {
                VStack(spacing: 2) {
                    // Core tabs (Journal, Dashboard, Analytics)
                    ForEach(SidebarTab.tabs(for: .core)) { tab in
                        sidebarRow(tab)
                    }

                    // Tools section
                    sectionHeader("TOOLS", isExpanded: $toolsExpanded)
                    if toolsExpanded {
                        ForEach(SidebarTab.tabs(for: .tools)) { tab in
                            sidebarRow(tab)
                        }
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer()

            // Bottom area
            VStack(spacing: 0) {
                if !appState.sidebarQuotes.isEmpty {
                    priceTicker
                }
                sessionClockWidget
            }
        }
        .background(Color.bgSidebar)
        .onReceive(timer) { time in
            currentTime = time
            // Track quote freshness for stale indicator
            let snapshot = appState.sidebarQuotes.prefix(5).map { "\($0.close)" }.joined()
            if !snapshot.isEmpty && snapshot != lastQuoteSnapshot {
                lastQuoteSnapshot = snapshot
                quotesLastUpdated = Date()
            }
        }
    }

    // MARK: - Logo Header

    private var logoHeader: some View {
        HStack(spacing: 8) {
            // App icon — load from asset catalog directly to avoid stale cache
            if let icon = NSImage(named: "AppIcon") {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Text("Dojix")
                .font(.logoText)
                .foregroundStyle(Color.textPrimary)

            Spacer()
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Navigation Row

    private func sidebarRow(_ tab: SidebarTab) -> some View {
        let isSelected = selectedTab == tab
        let isHovered = hoveredTab == tab

        return Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 10) {
                // Lucide icon with SF Symbol fallback
                Group {
                    if NSImage(named: tab.lucideIcon) != nil {
                        Image(tab.lucideIcon)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: tab.icon)
                    }
                }
                .frame(width: 18, height: 18)

                Text(tab.rawValue)
                    .font(.sidebarItem)
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.accent : Color.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        isSelected ? Color.accentDim :
                        isHovered ? Color(red: 1.0, green: 0.863, blue: 0.627, opacity: 0.04) :
                        Color.clear
                    )
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.accent)
                        .frame(width: 3, height: 18)
                        .offset(x: 0)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredTab = hovering ? tab : nil
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String, isExpanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack {
                Text(title)
                    .font(.sectionLabel)
                    .tracking(1.2)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
            }
            .padding(.horizontal, 12)
            .padding(.top, 16)
            .padding(.bottom, 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Price Ticker

    private static let sidebarMono = Font.custom("JetBrains Mono", size: 12)

    private var priceTicker: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.borderSubtle)
                .frame(height: 1)
            VStack(spacing: 3) {
                ForEach(appState.sidebarQuotes.prefix(5), id: \.symbol) { quote in
                    HStack(spacing: 4) {
                        Text(quote.symbol.replacingOccurrences(of: "/", with: ""))
                            .font(Self.sidebarMono)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.forPair(quote.symbol))
                            .lineLimit(1)
                            .fixedSize()

                        Text(Self.formatSidebarPrice(quote.close, symbol: quote.symbol))
                            .font(Self.sidebarMono)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)

                        Spacer(minLength: 2)

                        Text(String(format: "%+.2f%%", quote.changePercent))
                            .font(Self.sidebarMono)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.forPnL(quote.changePercent))
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                if let lastUpdated = quotesLastUpdated {
                    let isStale = currentTime.timeIntervalSince(lastUpdated) > 300
                    HStack(spacing: 3) {
                        Circle()
                            .fill(isStale ? Color.semanticAmber : Color.semanticGreen)
                            .frame(width: 4, height: 4)
                        Text(Self.localTimeFormatter.string(from: lastUpdated))
                            .font(.system(size: 10))
                            .foregroundStyle(isStale ? Color.semanticAmber : Color.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    /// Shorter price format for sidebar — 4 decimals for non-JPY, 2 for JPY
    private static func formatSidebarPrice(_ price: Double, symbol: String) -> String {
        let isJPY = symbol.contains("JPY")
        return String(format: isJPY ? "%.2f" : "%.4f", price)
    }


    // MARK: - Session Clock Widget

    private var sessionClockWidget: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.borderSubtle)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    // Pulsing gold session dot (respects Reduce Motion)
                    Circle()
                        .fill(Color.accent)
                        .frame(width: 8, height: 8)
                        .shadow(color: Color.accent.opacity(reduceMotion ? 0.4 : (dotGlowExpanded ? 0.6 : 0.2)),
                                radius: reduceMotion ? 4 : (dotGlowExpanded ? 6 : 2))
                        .onAppear {
                            guard !reduceMotion else { return }
                            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                                dotGlowExpanded = true
                            }
                        }

                    Text(currentSession.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)

                    Spacer()

                    Text(localTimeString)
                        .font(.monoSubtitle)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                }

                HStack {
                    Text("UTC \(utcTimeString)")
                        .font(.smallText)
                        .foregroundStyle(Color.textTertiary)
                    Spacer()
                    Text(timeRemainingText)
                        .font(.smallText)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Computed Properties

    private var currentSession: TradingSession {
        currentTime.tradingSession
    }

    private static let localTimeFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        fmt.timeZone = .current
        return fmt
    }()

    private static let utcTimeFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()

    private static let utcHourFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()

    private var localTimeString: String {
        Self.localTimeFormatter.string(from: currentTime)
    }

    private var utcTimeString: String {
        Self.utcTimeFormatter.string(from: currentTime)
    }

    private var timeRemainingText: String {
        let sessionEnd: Int
        switch currentSession {
        case .asian: sessionEnd = 9
        case .london: sessionEnd = 16
        case .nyOverlap: sessionEnd = 16
        case .ny: sessionEnd = 21
        case .late: sessionEnd = 24
        }

        let currentHourUTC = Int(Self.utcHourFormatter.string(from: currentTime)) ?? 0
        let hoursLeft = (sessionEnd - currentHourUTC + 24) % 24
        return "\(hoursLeft)h left"
    }
}
