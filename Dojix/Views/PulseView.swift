import SwiftUI

/// Live session intelligence — the "Pulse" pillar of Dojix
struct PulseView: View {
    @Environment(\.appState) private var appState
    @State private var viewModel = PulseViewModel()
    @State private var pulseAnimation = false
    @State private var expandedSessions: Set<TradingSession> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                sessionHero

                // Danger zone alert
                if let danger = viewModel.activeDangerZone {
                    dangerZoneAlert(danger)
                }

                edgeMatchBanner

                // Collapsible per-session cards
                ForEach(activeSessions, id: \.self) { session in
                    sessionCard(for: session)
                }

                sessionTimeline
                edgeAndCalendarGrid
                livePricesSection
            }
            .padding(20)
        }
        .navigationTitle("Pulse")
        .onAppear {
            if !reduceMotion { pulseAnimation = true }
            expandedSessions = Set(activeSessions)
        }
        .task { await viewModel.loadCalendar() }
        .task {
            await viewModel.startLiveData()
            appState.sidebarQuotes = viewModel.displayQuotes
        }
        .task {
            let trades = (try? appState.tradeRepository.fetchAll()) ?? []
            viewModel.setTrades(trades)
            viewModel.generateEdgeSignals(trades: trades)
        }
        .task { await viewModel.startAutoRefresh() }
        .onChange(of: viewModel.displayQuotes.map(\.close)) {
            // Keep the sidebar ticker in sync with REST and streaming prices
            appState.sidebarQuotes = viewModel.displayQuotes
        }
        .sheet(isPresented: $viewModel.showWatchlistEditor) {
            Task { await viewModel.startLiveData() }
        } content: {
            watchlistEditor
        }
    }

    // MARK: - Session Hero

    private var sessionHero: some View {
        VStack(spacing: 20) {
            // Top row: session name(s) + clock
            HStack {
                HStack(spacing: 16) {
                    // Session color dots
                    HStack(spacing: 6) {
                        ForEach(activeSessions, id: \.self) { session in
                            Circle()
                                .fill(Color.forSession(session))
                                .frame(width: 12, height: 12)
                                .shadow(color: Color.forSession(session).opacity(reduceMotion ? 0.3 : 0.5),
                                        radius: reduceMotion ? 6 : (pulseAnimation ? 12 : 4))
                                .animation(reduceMotion ? nil : .easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulseAnimation)
                        }
                    }

                    Text(activeSessions.count == 1
                         ? activeSessions[0].displayName
                         : "\(activeSessions.count) Sessions Active")
                        .font(.sessionName)

                    if activeSessions.count > 1 {
                        Text(activeSessions.map(\.displayName).joined(separator: " + "))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(Color.accentDim)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        Text("Active Session")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(Color.accentDim)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(localTimeString)
                        .font(.sessionClock)
                    Text("UTC \(utcTimeString)")
                        .font(.monoSubtitle)
                        .foregroundStyle(Color.textTertiary)
                }
            }

            // 3-column meta grid (equal height)
            HStack(alignment: .top, spacing: 16) {
                metaCard(
                    label: "Session",
                    icon: "circle.fill",
                    value: primarySessionName,
                    valueColor: Color.forSession(activeSessions.first ?? .london),
                    subtitle: "Active now"
                )
                metaCard(
                    label: "Time in Session",
                    icon: "clock",
                    value: timeInSession,
                    valueColor: .textPrimary,
                    subtitle: timeRemainingPrimary
                )
                metaCard(
                    label: "Next Session",
                    icon: "chevron.right",
                    value: nextSessionName,
                    valueColor: .semanticBlue,
                    subtitle: "Coming up"
                )
            }
        }
        .padding(24)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.borderCard, lineWidth: 1)
        )
        .accentTopBar()
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func metaCard(label: String, icon: String, value: String, valueColor: Color, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textTertiary)
                Text(label.uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color.textTertiary)
            }
            Text(value)
                .font(.system(.title3, design: .monospaced))
                .fontWeight(.bold)
                .foregroundStyle(valueColor)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(Color.textTertiary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
        .insetSurface()
    }

    // MARK: - Edge Match Banner

    @ViewBuilder
    private var edgeMatchBanner: some View {
        if let signal = viewModel.edgeSignal {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(bannerDimColor(signal.level))
                        .frame(width: 36, height: 36)
                    Image(systemName: edgeSignalIcon(signal.level))
                        .font(.system(size: 16))
                        .foregroundStyle(bannerColor(signal.level))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(signal.message)
                        .font(.system(size: 16, weight: .semibold))
                    Text(signal.details)
                        .font(.system(size: 16))
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()
            }
            .padding(14)
            .background(
                LinearGradient(
                    colors: [bannerColor(signal.level).opacity(0.08), bannerColor(signal.level).opacity(0.02)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(bannerColor(signal.level).opacity(0.15), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
       .overlay(
           RoundedRectangle(cornerRadius: 12)
               .stroke(Color.borderCard, lineWidth: 1)
       )
        }
    }

    // MARK: - Collapsible Session Card

    private func sessionCard(for session: TradingSession) -> some View {
        let isExpanded = expandedSessions.contains(session)
        let signal = viewModel.sessionEdgeSignals[session]
        let metrics = viewModel.sessionMetrics[session]

        return VStack(spacing: 0) {
            // Collapsed header — always visible
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedSessions.remove(session)
                    } else {
                        expandedSessions.insert(session)
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.forSession(session))
                        .frame(width: 12, height: 12)

                    Text(session.displayName)
                        .font(.cardTitle)

                    if let signal {
                        Image(systemName: edgeSignalIcon(signal.level))
                            .font(.caption)
                            .foregroundStyle(bannerColor(signal.level))
                    }

                    Spacer()

                    Text(timeRemainingFor(session))
                        .font(.monoSubtitle)
                        .foregroundStyle(Color.textSecondary)

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(16)

            // Expanded content
            if isExpanded {
                Divider()
                    .overlay(Color.borderSubtle)
                    .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 12) {
                    // Edge signal
                    if let signal {
                        HStack(spacing: 8) {
                            Image(systemName: edgeSignalIcon(signal.level))
                                .foregroundStyle(bannerColor(signal.level))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(signal.message)
                                    .font(.system(size: 16, weight: .semibold))
                                Text(signal.details)
                                    .font(.smallText)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                    }

                    // Metrics grid
                    if let metrics, metrics.totalTrades > 0 {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                            sessionMetricCell(
                                label: "Trades",
                                value: "\(metrics.totalTrades)"
                            )
                            sessionMetricCell(
                                label: "Win Rate",
                                value: String(format: "%.0f%%", metrics.winRate)
                            )
                            sessionMetricCell(
                                label: "PF",
                                value: String(format: "%.1f", metrics.profitFactor)
                            )
                            sessionMetricCell(
                                label: "P&L",
                                value: String(format: "$%.0f", metrics.totalProfit),
                                color: Color.forPnL(metrics.totalProfit)
                            )
                        }
                    } else {
                        Text("No trade history for this session yet")
                            .font(.smallText)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                .padding(16)
            }
        }
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
      .overlay(
          RoundedRectangle(cornerRadius: 12)
              .stroke(Color.borderCard, lineWidth: 1)
      )
    }

    private func sessionMetricCell(label: String, value: String, color: Color? = nil) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .fontWeight(.bold)
                .foregroundStyle(color ?? .primary)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .insetSurface()
    }

    // MARK: - Session Timeline

    private var sessionTimeline: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.semanticPurpleDim)
                        .frame(width: 22, height: 22)
                    Image(systemName: "clock")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.semanticPurple)
                }
                Text("Session Timeline")
                    .font(.cardTitle)
            }
            .padding(.bottom, 4)

            // Timeline bar
            GeometryReader { geo in
                let totalWidth = geo.size.width
                let currentHour = Date().utcHour
                let currentMinute = Calendar.current.component(.minute, from: Date())
                let progressFraction = (Double(currentHour) + Double(currentMinute) / 60.0) / 24.0

                // Segments: Asian 0-9, London 9-12, Overlap 12-16, NY 16-21, Late 21-24
                let segments: [(String, Color, Double)] = [
                    ("Asian", Color.semanticAmber, 9.0 / 24.0),
                    ("London", Color.semanticPurple, 3.0 / 24.0),
                    ("Overlap", Color.semanticGreen, 4.0 / 24.0),
                    ("New York", Color.semanticBlue, 5.0 / 24.0),
                    ("Late", Color.textTertiary, 3.0 / 24.0),
                ]

                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        ForEach(segments, id: \.0) { label, color, fraction in
                            ZStack {
                                Rectangle()
                                    .fill(color.opacity(0.12))
                                Text(label)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(color)
                            }
                            .frame(width: totalWidth * fraction, height: 40)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                   .overlay(

                       RoundedRectangle(cornerRadius: 12)

                           .stroke(Color.borderCard, lineWidth: 1)

                   )

                    // "Now" marker
                    Rectangle()
                        .fill(Color.textPrimary)
                        .frame(width: 2, height: 48)
                        .shadow(color: Color.textPrimary.opacity(0.3), radius: 4)
                        .offset(x: totalWidth * progressFraction)
                }
            }
            .frame(height: 48)

            // Time labels
            HStack {
                Text("00:00")
                Spacer()
                Text("07:00")
                Spacer()
                Text("12:00")
                Spacer()
                Text("16:00")
                Spacer()
                Text("21:00")
            }
            .font(.monoSubtitle)
            .foregroundStyle(Color.textTertiary)
        }
        .padding(20)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
      .overlay(
          RoundedRectangle(cornerRadius: 12)
              .stroke(Color.borderCard, lineWidth: 1)
      )
    }


    // MARK: - Edge Stats + Calendar Grid

    private var edgeAndCalendarGrid: some View {
        HStack(alignment: .top, spacing: 16) {
            edgeStatsCard
            economicCalendarCard
        }
    }

    // MARK: - Edge Stats Card

    private var edgeStatsCard: some View {
        let primarySession = activeSessions.first ?? .london
        let metrics = viewModel.sessionMetrics[primarySession]

        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.semanticGreenDim)
                            .frame(width: 22, height: 22)
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.semanticGreen)
                    }
                    Text("Your \(primarySession.displayName) Edge")
                        .font(.cardTitle)
                }
                Spacer()
                if let m = metrics, m.totalTrades > 0 {
                    Text(m.winRate.asPercent + " WR")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Color.semanticGreenDim)
                        .foregroundStyle(Color.semanticGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            if let m = metrics, m.totalTrades > 0 {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    edgeStatCell(label: "P&L", value: m.totalProfit.asCurrency, color: Color.forPnL(m.totalProfit))
                    edgeStatCell(label: "Trades", value: "\(m.totalTrades)", color: .textPrimary)
                    edgeStatCell(label: "Avg R", value: m.averageRMultiple.asRMultiple, color: .semanticBlue)
                    edgeStatCell(label: "Best Pair", value: bestPairForSession(metrics: m), color: .semanticPurple, isSmallText: true)
                    edgeStatCell(label: "Best Hour", value: bestHourString, color: .semanticAmber)
                    edgeStatCell(label: "Avg Duration", value: "\(m.averageDuration)m", color: .textPrimary)
                }
            } else {
                Text("No trade history for this session yet")
                    .font(.bodyText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 100)
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

    private func edgeStatCell(label: String, value: String, color: Color, isSmallText: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 13, weight: .medium))
                .tracking(0.4)
                .foregroundStyle(Color.textTertiary)
            Text(value)
                .font(isSmallText ? .system(size: 16, weight: .bold, design: .monospaced) : .system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .insetSurface()
    }

    // MARK: - Economic Calendar Card

    private var economicCalendarCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.accentDim)
                            .frame(width: 22, height: 22)
                        Image(systemName: "calendar")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.accent)
                    }
                    Text("Economic Calendar")
                        .font(.cardTitle)
                }
                Spacer()
                if viewModel.isLoadingCalendar {
                    ProgressView()
                        .controlSize(.small)
                }
                Text("This Week")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textTertiary)
            }

            if let error = viewModel.calendarError {
                Text(error)
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
            } else if viewModel.calendarEvents.isEmpty && !viewModel.isLoadingCalendar {
                Text("No economic events this week")
                    .font(.bodyText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                VStack(spacing: 8) {
                    ForEach(calendarDayGroups, id: \.date) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            // Day header
                            HStack(spacing: 6) {
                                Text(group.dayLabel)
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundStyle(group.isToday ? Color.accent : Color.textSecondary)
                                if group.isToday {
                                    Text("TODAY")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Color.accent)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.accentDim)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                                let highCount = group.events.filter { $0.impact == .high }.count
                                if highCount > 0 {
                                    Text("\(highCount) high-impact")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.semanticRed)
                                }
                                Spacer()
                            }
                            .padding(.top, group.isToday ? 0 : 4)

                            ForEach(group.events) { event in
                                eventRow(event)
                            }
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

    private func eventRow(_ event: CalendarService.EconomicEvent) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Time
                Text(event.date.formatted(.dateTime.hour().minute()))
                    .font(.monoSubtitle)
                    .foregroundStyle(Color.textTertiary)
                    .frame(width: 48, alignment: .leading)

                // Impact dot
                Circle()
                    .fill(colorForImpact(event.impact))
                    .frame(width: 8, height: 8)
                    .shadow(color: event.impact == .high ? Color.semanticRed.opacity(0.4) : .clear, radius: 3)

                // Currency badge
                Text(event.country)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .frame(width: 32)
                    .padding(.vertical, 2)
                    .background(Color.borderSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                // Event title
                Text(event.title)
                    .font(.system(size: 15))
                    .lineLimit(1)

                Spacer()

                // Forecast / Previous
                if let forecast = event.forecast {
                    VStack(spacing: 1) {
                        Text("FCST")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.textTertiary)
                        Text(forecast)
                            .font(.monoSubtitle)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                if let actual = event.actual {
                    Text(actual)
                        .font(.monoSubtitle)
                        .fontWeight(.bold)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            // Historical performance for high-impact events
            if event.impact == .high, let history = viewModel.eventHistory(for: event) {
                Divider().overlay(Color.borderCard)
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                    Text("Your history:")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textTertiary)
                    Text("\(history.wins)W/\(history.losses)L")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(history.wins > history.losses ? Color.semanticGreen : Color.semanticRed)
                    Text(String(format: "%+.2f avg", history.avgPnL))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.forPnL(history.avgPnL))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.bgContent)
            }
        }
        .background(Color.bgInset)
        .clipShape(RoundedRectangle(cornerRadius: 12))
       .overlay(
           RoundedRectangle(cornerRadius: 12)
               .stroke(Color.borderCard, lineWidth: 1)
       )
        .opacity(event.date < Date() ? 0.5 : 1.0)
    }

    // MARK: - Live Prices

    private var livePricesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.semanticBlueDim)
                            .frame(width: 22, height: 22)
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.semanticBlue)
                    }
                    Text("Live Prices")
                        .font(.cardTitle)
                }
                // Streaming status indicator
                if viewModel.liveDataManager.isStreaming {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.profitGreen)
                            .frame(width: 6, height: 6)
                        Text("Streaming")
                            .font(.smallText)
                            .foregroundStyle(Color.profitGreen)
                    }
                } else if let refreshText = viewModel.lastRefreshText {
                    Text(refreshText)
                        .font(.smallText)
                        .foregroundStyle(Color.textTertiary)
                }
                Spacer()
                if viewModel.isLoadingQuotes || viewModel.liveDataManager.status == .connecting {
                    ProgressView()
                        .controlSize(.small)
                }
                Button {
                    viewModel.showWatchlistEditor = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Edit watchlist")
                Button {
                    Task { await viewModel.startLiveData() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
            }

            if let error = viewModel.liveQuotesError {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Color.textSecondary)
                        .font(.smallText)
                    Text(error)
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                }
            } else if viewModel.displayQuotes.isEmpty && !viewModel.isLoadingQuotes {
                Text(viewModel.liveDataManager.activeSource.isStreaming
                     ? "Waiting for prices from \(viewModel.liveDataManager.activeSource.displayName)..."
                     : "Live prices are optional: add your own Twelve Data API key in Settings")
                    .font(.bodyText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                VStack(spacing: 4) {
                    ForEach(viewModel.displayQuotes, id: \.symbol) { quote in
                        watchlistRow(quote)
                    }
                }

                // Currency strength
                if !viewModel.currencyStrength.isEmpty {
                    currencyStrengthSection
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

    private func watchlistRow(_ quote: TwelveDataService.Quote) -> some View {
        HStack(spacing: 12) {
            Text(quote.symbol)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.forPair(quote.symbol))
                .lineLimit(1)
                .fixedSize()

            Text(String(format: quote.symbol.contains("JPY") ? "%.3f" : "%.5f", quote.close))
                .font(.system(size: 15, design: .monospaced))
                .lineLimit(1)

            Spacer()

            Text(String(format: "%+.2f%%", quote.changePercent))
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(quote.changePercent >= 0 ? Color.semanticGreenDim : Color.semanticRedDim)
                .foregroundStyle(quote.changePercent >= 0 ? Color.semanticGreen : Color.semanticRed)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.bgInset)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.borderCard, lineWidth: 1)
        )
    }

    private var currencyStrengthSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Currency Strength")
                .font(.system(size: 16, weight: .semibold))
                .padding(.top, 8)

            ForEach(viewModel.currencyStrength, id: \.currency) { item in
                HStack(spacing: 8) {
                    Text(item.currency)
                        .font(.monoSubtitle)
                        .fontWeight(.medium)
                        .frame(width: 30)

                    GeometryReader { geo in
                        let width = geo.size.width
                        let barWidth = abs(item.strength) * width / 2
                        let isPositive = item.strength >= 0

                        ZStack(alignment: isPositive ? .leading : .trailing) {
                            Rectangle()
                                .fill(Color.bgInset)
                                .frame(height: 12)

                            Rectangle()
                                .fill(isPositive ? Color.semanticGreen : Color.semanticRed)
                                .frame(width: barWidth, height: 12)
                                .offset(x: isPositive ? width / 2 : width / 2 - barWidth)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    .frame(height: 12)

                    Text(String(format: "%+.1f%%", item.strength * 100))
                        .font(.monoSubtitle)
                        .foregroundStyle(Color.forPnL(item.strength))
                        .frame(width: 50, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - Danger Zone Alert

    private func dangerZoneAlert(_ danger: CalendarService.DangerZone) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.semanticRedDim)
                    .frame(width: 36, height: 36)
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.semanticRed)
                    .font(.system(size: 16))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Danger Zone Active")
                    .font(.system(size: 16, weight: .bold))

                Text("\(danger.event.title) (\(danger.event.country))")
                    .font(.smallText)

                if !danger.affectedPairs.isEmpty {
                    Text("Avoid: \(danger.affectedPairs.joined(separator: ", "))")
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            Spacer()
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color.semanticRed.opacity(0.08), Color.semanticRed.opacity(0.02)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.semanticRed.opacity(0.15), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
   .overlay(
       RoundedRectangle(cornerRadius: 12)
           .stroke(Color.borderCard, lineWidth: 1)
   )
    }

    // MARK: - Helpers

    private var activeSessions: [TradingSession] {
        Date().activeTradingSessions
    }

    private var primarySessionName: String {
        if activeSessions.count == 1 {
            return activeSessions[0].displayName
        }
        // Prefer London or NY over overlap for display
        if let london = activeSessions.first(where: { $0 == .london }) {
            return london.displayName
        }
        return activeSessions.first?.displayName ?? "No Session"
    }

    private var nextSessionName: String {
        let h = Date().utcHour
        if h < 7 { return "London" }
        if h < 12 { return "NY Overlap" }
        if h < 16 { return "New York" }
        if h < 21 { return "Late" }
        return "Asian"
    }

    private var timeInSession: String {
        guard let primary = activeSessions.first else { return "--" }
        let h = Date().utcHour
        let hoursIn = (h - primary.startHourUTC + 24) % 24
        return "\(hoursIn)h"
    }

    private var timeRemainingPrimary: String {
        guard let primary = activeSessions.first else { return "" }
        return timeRemainingFor(primary)
    }

    private var bestHourString: String {
        // Show current hour as fallback
        let h = Date().utcHour
        return String(format: "%02d:00", h)
    }

    private func bestPairForSession(metrics: MetricsCalculator.PortfolioMetrics) -> String {
        // Placeholder — would need per-pair breakdown from session trades
        return "—"
    }

    private var localTimeString: String {
        Date().formatted(.dateTime.hour().minute().second())
    }

    private var utcTimeString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt.string(from: Date())
    }

    private func timeRemainingFor(_ session: TradingSession) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH"
        fmt.timeZone = TimeZone(identifier: "UTC")
        let currentHourUTC = Int(fmt.string(from: Date())) ?? 0
        let minuteComponent = Calendar.current.component(.minute, from: Date())

        let endHour = session.endHourUTC
        let hoursLeft = (endHour - currentHourUTC + 24) % 24
        let minutesLeft = 60 - minuteComponent

        if hoursLeft == 0 {
            return "\(minutesLeft)m remaining"
        } else if hoursLeft == 1 && minutesLeft < 60 {
            return "1h \(minutesLeft)m remaining"
        }
        return "\(hoursLeft)h remaining"
    }

    // MARK: - Signal Helpers

    private func edgeSignalIcon(_ level: EdgeSignal.Level) -> String {
        switch level {
        case .strong: "checkmark.seal.fill"
        case .neutral: "equal.circle.fill"
        case .avoid: "hand.raised.fill"
        }
    }

    private func bannerColor(_ level: EdgeSignal.Level) -> Color {
        switch level {
        case .strong: .semanticGreen
        case .neutral: .orange
        case .avoid: .semanticRed
        }
    }

    private func bannerDimColor(_ level: EdgeSignal.Level) -> Color {
        switch level {
        case .strong: .semanticGreenDim
        case .neutral: Color.orange.opacity(0.14)
        case .avoid: .semanticRedDim
        }
    }

    // MARK: - Calendar Day Groups

    private struct CalendarDayGroup {
        let date: Date
        let dayLabel: String
        let isToday: Bool
        let events: [CalendarService.EconomicEvent]
    }

    private var calendarDayGroups: [CalendarDayGroup] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: viewModel.calendarEvents) { event in
            cal.startOfDay(for: event.date)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"

        return grouped.keys.sorted().map { date in
            CalendarDayGroup(
                date: date,
                dayLabel: formatter.string(from: date).uppercased(),
                isToday: cal.isDateInToday(date),
                events: grouped[date] ?? []
            )
        }
    }

    private func colorForImpact(_ impact: CalendarService.Impact) -> Color {
        switch impact {
        case .high: .semanticRed
        case .medium: .orange
        case .low: .textTertiary
        }
    }

    // MARK: - Watchlist Editor

    private var watchlistEditor: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Edit Watchlist")
                    .font(.cardTitle)
                Spacer()
                Button("Reset to Defaults") {
                    viewModel.watchlistPairs = PulseViewModel.defaultPairs
                }
                .font(.smallText)
            }

            Text("Select up to 8 pairs to display in Live Prices.")
                .font(.bodyText)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            let currentPairs = viewModel.watchlistPairs

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(PulseViewModel.availablePairs, id: \.self) { pair in
                        let isSelected = currentPairs.contains(pair)
                        Button {
                            togglePair(pair)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isSelected ? Color.semanticGreen : Color.textTertiary)
                                    .font(.smallText)
                                Text(pair)
                                    .font(.monoSubtitle)
                                    .foregroundStyle(Color.forPair(pair))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(isSelected ? Color.semanticGreenDim : Color.bgInset)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                       .overlay(
                           RoundedRectangle(cornerRadius: 12)
                               .stroke(Color.borderCard, lineWidth: 1)
                       )
                        }
                        .buttonStyle(.plain)
                        .disabled(!isSelected && currentPairs.count >= 8)
                    }
                }
            }
            .frame(maxHeight: 300)

            HStack {
                Text("\(currentPairs.count)/8 pairs selected")
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Button("Done") {
                    viewModel.showWatchlistEditor = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func togglePair(_ pair: String) {
        var pairs = viewModel.watchlistPairs
        if let index = pairs.firstIndex(of: pair) {
            pairs.remove(at: index)
        } else {
            pairs.append(pair)
        }
        viewModel.watchlistPairs = pairs
    }
}
