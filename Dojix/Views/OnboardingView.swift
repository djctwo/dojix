import SwiftUI

/// Onboarding tour — adaptive based on experience level
/// First launch: shows experience picker, then tailored flow.
/// Subsequent launches: skippable and can be disabled.
struct OnboardingView: View {
    @Environment(\.appState) private var appState
    let isFirstTime: Bool

    enum ExperienceLevel {
        case none       // haven't picked yet
        case beginner   // "I'm new to trade journaling"
        case expert     // "I know what I'm doing"
    }

    @Environment(\.openWindow) private var openWindow
    @State private var currentStep = 0
    @State private var experience: ExperienceLevel = .none
    @State private var apiKey = ""
    @State private var mt5Path = Configuration.mt5PrimaryFolder
    @State private var showDemoConfirmation = false

    /// Experts skip the feature tour — welcome, setup, ready
    private var steps: [Int] {
        switch experience {
        case .none: [0]
        case .beginner: Array(0...7)
        case .expert: [0, 6, 7]  // welcome → setup → ready
        }
    }

    private var totalSteps: Int { steps.count }

    private var currentStepIndex: Int {
        steps[min(currentStep, steps.count - 1)]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar: skip + progress dots
            HStack {
                // Skip button — always available (experts shouldn't be forced)
                Button("Skip") {
                    appState.onboarding.completeOnboarding()
                }
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)

                Spacer()

                if experience != .none {
                    // Progress dots
                    HStack(spacing: 6) {
                        ForEach(0..<totalSteps, id: \.self) { step in
                            Circle()
                                .fill(step <= currentStep ? Color.accent : Color.secondary.opacity(0.3))
                                .frame(width: 7, height: 7)
                        }
                    }

                    Spacer()

                    // Step counter
                    Text("\(currentStep + 1)/\(totalSteps)")
                        .font(.smallText)
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 40)
                } else {
                    Spacer()
                }
            }
            .padding(.top, 24)
            .padding(.horizontal, 24)

            Spacer()

            // Step content
            Group {
                if experience == .none {
                    welcomeStep
                } else {
                    switch currentStepIndex {
                    case 0: welcomeStep
                    case 1: importStep
                    case 2: journalStep
                    case 3: dashboardStep
                    case 4: edgeReportStep
                    case 5: pulseStep
                    case 6: setupStep
                    case 7: readyStep
                    default: readyStep
                    }
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

            Spacer()

            // Navigation
            HStack {
                if experience != .none && currentStep > 0 {
                    Button("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                    .controlSize(.large)
                }

                Spacer()

                if experience == .none {
                    // Experience picker buttons
                    EmptyView()
                } else if currentStep < totalSteps - 1 {
                    Button {
                        saveCurrentStep()
                        withAnimation { currentStep += 1 }
                    } label: {
                        Text("Next")
                            .frame(minWidth: 100)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .tint(.accent)
                } else {
                    VStack(spacing: 8) {
                        Button {
                            saveCurrentStep()
                            appState.onboarding.completeOnboarding()
                        } label: {
                            Text("Start Trading")
                                .frame(minWidth: 120)
                        }
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                        .tint(.accent)

                        if !isFirstTime {
                            Button {
                                appState.onboarding.disableTourOnLaunch()
                                appState.onboarding.completeOnboarding()
                            } label: {
                                Text("Don't show this again")
                                    .font(.smallText)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.textTertiary)
                        }
                    }
                }
            }
            .padding(.bottom, 28)
        }
        .padding(.horizontal, 60)
        .frame(width: 700, height: 580)
    }

    // MARK: - Step 1: Welcome (with experience picker)

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(Color.accent)
                .symbolRenderingMode(.hierarchical)

            Text("Welcome to Dojix")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Free and open source. Every feature is included.")
                .font(.body)
                .foregroundStyle(Color.textSecondary)

            if experience == .none {
                Text("How would you describe your experience?")
                    .font(.title3)
                    .foregroundStyle(Color.textSecondary)

                VStack(spacing: 12) {
                    experienceButton(
                        title: "I'm new to trade journaling",
                        desc: "Show me what everything means — sessions, R-multiples, edge detection",
                        icon: "graduationcap",
                        level: .beginner
                    )
                    experienceButton(
                        title: "I know what I'm doing",
                        desc: "Skip the tour — take me straight to import",
                        icon: "bolt",
                        level: .expert
                    )
                }
                .frame(maxWidth: 440)
            } else if experience == .beginner {
                Text("Your trading edge, quantified.")
                    .font(.title3)
                    .foregroundStyle(Color.textSecondary)

                VStack(alignment: .leading, spacing: 14) {
                    featureRow(icon: "square.and.arrow.down", title: "Multi-Platform Import", desc: "MT5, MT4, cTrader, OANDA, TradingView, and more")
                    featureRow(icon: "list.bullet.rectangle", title: "Trade Journal", desc: "Every trade logged with full analytics and grading")
                    featureRow(icon: "chart.bar.xaxis", title: "66 Analytics", desc: "Dashboard, equity curves, Monte Carlo, correlations")
                    featureRow(icon: "brain", title: "AI Edge Detection", desc: "Claude-powered trade recommendations")
                    featureRow(icon: "clock", title: "Live Session Intelligence", desc: "Session clock, live quotes, economic calendar")
                }
                .padding(.top, 4)
            } else {
                // Expert returning to welcome via Back — keep it clean
                Text("Your trading edge, quantified.")
                    .font(.title3)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    private func experienceButton(title: String, desc: String, icon: String, level: ExperienceLevel) -> some View {
        Button {
            withAnimation {
                experience = level
                currentStep = 0
                if level == .expert {
                    // Jump past welcome to setup
                    currentStep = 1
                }
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(Color.accent)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.textPrimary)
                    Text(desc)
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(16)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.borderCard, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 2: Import

    private var importStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 56))
                .foregroundStyle(Color.accent)
                .symbolRenderingMode(.hierarchical)

            Text("Import Your Trades")
                .font(.title)
                .fontWeight(.bold)

            Text("Dojix auto-detects your CSV format. Just drag and drop — no manual setup needed.")
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            VStack(alignment: .leading, spacing: 8) {
                Text("Supported Platforms")
                    .font(.smallText)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.textSecondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 6) {
                    platformBadge("StrategyAnalytics (MT5)", icon: "chart.bar.doc.horizontal")
                    platformBadge("MetaTrader 4", icon: "chart.line.uptrend.xyaxis")
                    platformBadge("cTrader", icon: "arrow.left.arrow.right")
                    platformBadge("OANDA (CSV + API)", icon: "dollarsign.circle")
                    platformBadge("TradingView", icon: "tv")
                    platformBadge("Interactive Brokers", icon: "building.columns")
                    platformBadge("Thinkorswim", icon: "waveform.path.ecg")
                    platformBadge("NinjaTrader", icon: "flame")
                    platformBadge("Any CSV (manual map)", icon: "doc.text")
                }
            }
            .padding(14)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
           .overlay(
               RoundedRectangle(cornerRadius: 12)
                   .stroke(Color.borderCard, lineWidth: 1)
           )
            .frame(maxWidth: 500)

            Text("Unknown formats? A column mapping tool lets you map any CSV.")
                .font(.smallText)
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Step 3: Journal

    private var journalStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "list.bullet.rectangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.accent)
                .symbolRenderingMode(.hierarchical)

            Text("Trade Journal")
                .font(.title)
                .fontWeight(.bold)

            Text("Every trade at a glance — sortable, filterable, searchable.")
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            VStack(alignment: .leading, spacing: 10) {
                journalFeature("10-column trade table", desc: "Pair, direction, lots, P&L, R-multiple, session, grade, cumulative P&L")
                if experience == .beginner {
                    definitionCard(
                        ("R-Multiple", "Your profit as a multiple of your risk. If you risked $100 and made $200, that's 2R. Helps compare trades regardless of size."),
                        ("Grade (A-F)", "Automatic score based on how well you executed — timing, risk management, and whether you let winners run.")
                    )
                }
                journalFeature("Auto-grading (A-F)", desc: "Scores on R-multiple, execution, timing, and trade management")
                journalFeature("Filters & search", desc: "By symbol, session, direction, date range. Full-text search.")
                journalFeature("Trade notes & tags", desc: "Annotate trades with notes and custom tags")
                journalFeature("Trade Replay", desc: "Step through trades chronologically with running equity curve")
                journalFeature("PDF & CSV export", desc: "Export journal or share individual trade summaries")
            }
            .padding(14)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
           .overlay(
               RoundedRectangle(cornerRadius: 12)
                   .stroke(Color.borderCard, lineWidth: 1)
           )
            .frame(maxWidth: 500)
        }
    }

    // MARK: - Step 4: Dashboard

    private var dashboardStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 56))
                .foregroundStyle(Color.accent)
                .symbolRenderingMode(.hierarchical)

            Text("Dashboard & Analytics")
                .font(.title)
                .fontWeight(.bold)

            Text("66 analytics — the most comprehensive forex analytics dashboard available.")
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            if experience == .beginner {
                // Beginner: focus on what matters, not the full list
                VStack(alignment: .leading, spacing: 10) {
                    Text("What you'll see first")
                        .font(.smallText)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.accent)
                    journalFeature("Daily Brief", desc: "Your top 3 actionable insights — plain English, with dollar amounts")
                    journalFeature("Equity curve", desc: "Your account balance over time — are you growing or shrinking?")
                    journalFeature("Edge breakdown", desc: "Which sessions, hours, and pairs make you money vs lose money")
                    definitionCard(
                        ("Profit Factor", "Gross profit divided by gross loss. Above 1.0 = profitable. Above 1.5 = strong."),
                        ("Expectancy", "How much you expect to make per trade on average. Positive = you have an edge.")
                    )
                    Text("Start with the Essential view — you can switch to All Analytics anytime.")
                        .font(.smallText)
                        .foregroundStyle(Color.textTertiary)
                        .italic()
                }
                .padding(14)
                .background(Color.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: 12))
               .overlay(
                   RoundedRectangle(cornerRadius: 12)
                       .stroke(Color.borderCard, lineWidth: 1)
               )
                .frame(maxWidth: 500)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Performance")
                            .font(.smallText)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.accent)
                        analyticItem("Equity curve & drawdown")
                        analyticItem("Win rate, PF, expectancy")
                        analyticItem("Sharpe & Calmar ratios")
                        analyticItem("Monthly P&L table")
                        analyticItem("Growth projection")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Edge Detection")
                            .font(.smallText)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.accent)
                        analyticItem("Session & hour heatmaps")
                        analyticItem("Pair correlation matrix")
                        analyticItem("Monte Carlo simulation")
                        analyticItem("Behavioral analytics")
                        analyticItem("Sequence analysis")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Risk & Tools")
                            .font(.smallText)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.accent)
                        analyticItem("Risk of ruin (Kelly)")
                        analyticItem("Position sizer")
                        analyticItem("Prop firm tracker")
                        analyticItem("Consistency score")
                        analyticItem("Benchmark comparison")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(14)
                .background(Color.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: 12))
               .overlay(
                   RoundedRectangle(cornerRadius: 12)
                       .stroke(Color.borderCard, lineWidth: 1)
               )
                .frame(maxWidth: 540)
            }

            Text("Filter by date range and symbol. Export to PDF or CSV.")
                .font(.smallText)
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Step 5: Edge Report

    private var edgeReportStep: some View {
        VStack(spacing: 20) {
            Text("Edge Report & AI")
                .font(.title)
                .fontWeight(.bold)

            Text("Know exactly where you make and lose money — then let AI surface what you're missing.")
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)

            // Side-by-side makers vs losers preview
            HStack(alignment: .top, spacing: 12) {
                // Where you make money
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(Color.semanticGreen)
                        Text("Where You Make Money")
                            .font(.smallText)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.semanticGreen)
                    }
                    mockEdgeRow("#1", label: "London", pnl: "+$847", color: .semanticGreen)
                    mockEdgeRow("#2", label: "GBPUSD", pnl: "+$612", color: .semanticGreen)
                    mockEdgeRow("#3", label: "10:00 UTC", pnl: "+$445", color: .semanticGreen)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.semanticGreen.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.semanticGreen.opacity(0.15), lineWidth: 1)
                )

                // Where you lose money
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(Color.semanticRed)
                        Text("Where You Lose Money")
                            .font(.smallText)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.semanticRed)
                    }
                    mockEdgeRow("#1", label: "Late NY", pnl: "-$523", color: .semanticRed)
                    mockEdgeRow("#2", label: "Friday", pnl: "-$318", color: .semanticRed)
                    mockEdgeRow("#3", label: "USDJPY", pnl: "-$247", color: .semanticRed)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.semanticRed.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.semanticRed.opacity(0.15), lineWidth: 1)
                )
            }
            .frame(maxWidth: 500)

            // Additional features below
            VStack(alignment: .leading, spacing: 8) {
                journalFeature("Bias & volatility", desc: "Performance by trend alignment and market conditions")
                journalFeature("Post-close analysis", desc: "Are you exiting too early? See what happens after you close")
                journalFeature("AI recommendations", desc: "3-5 ranked suggestions with dollar impact via Claude API")
            }
            .padding(14)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.borderCard, lineWidth: 1)
            )
            .frame(maxWidth: 500)
        }
    }

    // MARK: - Step 6: Pulse

    private var pulseStep: some View {
        VStack(spacing: 20) {
            Text("Pulse — Live Intelligence")
                .font(.title)
                .fontWeight(.bold)

            Text("Real-time market context so you know when to trade and when to sit out.")
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)

            // Side-by-side: mock session clock + feature list
            HStack(alignment: .top, spacing: 16) {
                // Mock session clock widget
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.accent)
                            .frame(width: 10, height: 10)
                            .shadow(color: Color.accent.opacity(0.4), radius: 4)
                        Text("London")
                            .font(.system(size: 18, weight: .bold))
                        Spacer()
                        Text("14:32:15")
                            .font(.custom("JetBrains Mono", size: 14))
                            .foregroundStyle(Color.textSecondary)
                    }
                    HStack {
                        Text("UTC 12:32:15")
                            .font(.smallText)
                            .foregroundStyle(Color.textTertiary)
                        Spacer()
                        Text("4h left")
                            .font(.smallText)
                            .foregroundStyle(Color.textTertiary)
                    }

                    Rectangle()
                        .fill(Color.borderSubtle)
                        .frame(height: 1)

                    // Mock quotes
                    VStack(spacing: 4) {
                        mockQuoteRow("EURUSD", price: "1.0847", change: "+0.12%", positive: true)
                        mockQuoteRow("GBPUSD", price: "1.2634", change: "-0.08%", positive: false)
                        mockQuoteRow("USDJPY", price: "154.21", change: "+0.31%", positive: true)
                    }

                    Rectangle()
                        .fill(Color.borderSubtle)
                        .frame(height: 1)

                    // Mock edge signal
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.semanticGreen)
                        Text("Your London WR: 68%")
                            .font(.smallText)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.semanticGreen)
                    }
                }
                .padding(14)
                .background(Color.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.borderCard, lineWidth: 1)
                )
                .frame(maxWidth: 220)

                // Feature list
                VStack(alignment: .leading, spacing: 10) {
                    if experience == .beginner {
                        definitionCard(
                            ("Sessions", "Forex markets trade in sessions: Asian (Tokyo), London, and New York. Overlaps are often the most active."),
                            ("Edge Signal", "A personalized recommendation based on YOUR history. Green = you do well now. Red = sit this one out.")
                        )
                    }
                    journalFeature("Live forex quotes", desc: "Customizable watchlist via Twelve Data, OANDA, or Polygon.io")
                    journalFeature("Economic calendar", desc: "Full week view with danger zone alerts and historical performance")
                    journalFeature("Currency strength", desc: "Real-time strength bars for major currencies")
                    journalFeature("Edge signal", desc: "Personalized signal based on your history + current conditions")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: 540)

            Text("Live data requires a free Twelve Data API key (800 requests/day).")
                .font(.smallText)
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Step 7: Setup

    private var setupStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "gearshape.2.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.accent)
                .symbolRenderingMode(.hierarchical)

            Text("Quick Setup")
                .font(.title)
                .fontWeight(.bold)

            Text("Optional — you can configure these later in Settings.")
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 16) {
                // MT5 Path
                VStack(alignment: .leading, spacing: 6) {
                    Text("MT5 Common Files Path")
                        .font(.smallText)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.textSecondary)

                    HStack {
                        TextField("Path to MT5 Common Files", text: $mt5Path)
                            .textFieldStyle(.roundedBorder)
                            .font(.monoSubtitle)

                        Button("Browse") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            panel.message = "Select your MT5 Common Files directory"
                            if panel.runModal() == .OK, let url = panel.url {
                                mt5Path = url.path
                            }
                        }
                    }

                    HStack(spacing: 4) {
                        let exists = FileManager.default.fileExists(atPath: mt5Path)
                        Image(systemName: exists ? "checkmark.circle.fill" : "info.circle")
                            .foregroundStyle(exists ? .green : .secondary)
                            .font(.smallText)
                        Text(exists ? "Folder found" : "Not found — set later in Settings, or just drag-drop CSVs")
                            .font(.smallText)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                Divider()

                // API Key
                VStack(alignment: .leading, spacing: 6) {
                    Text("Anthropic API Key (optional — for AI analysis)")
                        .font(.smallText)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.textSecondary)

                    SecureField("sk-ant-...", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    Text("Get yours at console.anthropic.com")
                        .font(.smallText)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .padding(14)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
           .overlay(
               RoundedRectangle(cornerRadius: 12)
                   .stroke(Color.borderCard, lineWidth: 1)
           )
            .frame(maxWidth: 480)
        }
    }

    // MARK: - Step 8: Ready

    private var readyStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 72))
                .foregroundStyle(Color.semanticGreen)
                .symbolRenderingMode(.hierarchical)

            Text("You're All Set")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Import your first CSV to start quantifying your edge.")
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            VStack(alignment: .leading, spacing: 12) {
                quickStart(number: "1", text: "Go to Import — drop any trading platform CSV")
                quickStart(number: "2", text: "Check Dashboard for your top insights")
                quickStart(number: "3", text: "Open Edge Report to see where you make and lose money")
                quickStart(number: "4", text: "Use Pulse for live session context while you trade")
            }
            .padding(16)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.borderCard, lineWidth: 1)
            )

            HStack(spacing: 16) {
                Button {
                    showDemoConfirmation = true
                } label: {
                    Label("Load Sample Trades", systemImage: "sparkles")
                        .font(.smallText)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accent)

                Text("|")
                    .foregroundStyle(Color.textTertiary)

                Button {
                    openWindow(id: "help")
                } label: {
                    Label("Open Help (Cmd+?)", systemImage: "questionmark.circle")
                        .font(.smallText)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.textSecondary)
            }
            .alert("Load Sample Trades?", isPresented: $showDemoConfirmation) {
                Button("Load") { loadDemoData() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will add 30 sample trades to your journal. You can remove them later in Settings > Data Management.")
            }
        }
    }

    private func loadDemoData() {
        let trades = DemoDataGenerator.generateTrades()
        do {
            let count = try appState.tradeRepository.bulkInsert(trades)
            appState.showToast(.success, "Loaded \(count) sample trades")
        } catch {
            appState.showToast(.error, "Failed to load sample data")
        }
    }

    // MARK: - Helpers

    private func featureRow(icon: String, title: String, desc: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(desc)
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    private func journalFeature(_ title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.semanticGreen)
                .frame(width: 14, alignment: .center)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.smallText)
                    .fontWeight(.medium)
                Text(desc)
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    private func analyticItem(_ text: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 4, height: 4)
            Text(text)
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private func platformBadge(_ name: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Color.accent)
                .frame(width: 12)
            Text(name)
                .font(.smallText)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
    }

    private func quickStart(number: String, text: String) -> some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.bold)
                .foregroundStyle(Color.accent)
                .frame(width: 28)
            Text(text)
                .font(.body)
        }
    }

    /// Inline definition card for beginner onboarding — explains jargon
    /// Accepts any number of (term, definition) pairs
    private func definitionCard(_ items: (String, String)...) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accent)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.0)
                            .font(.smallText)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.textPrimary)
                        Text(item.1)
                            .font(.smallText)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.accentDim)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func mockEdgeRow(_ rank: String, label: String, pnl: String, color: Color) -> some View {
        HStack {
            Text(rank)
                .font(.smallText)
                .fontWeight(.bold)
                .foregroundStyle(Color.textSecondary)
                .frame(width: 20)
            Text(label)
                .font(.monoSubtitle)
            Spacer()
            Text(pnl)
                .font(.monoSubtitle)
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
    }

    private func mockQuoteRow(_ pair: String, price: String, change: String, positive: Bool) -> some View {
        HStack {
            Text(pair)
                .font(.custom("JetBrains Mono", size: 11))
                .fontWeight(.medium)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(price)
                .font(.custom("JetBrains Mono", size: 11))
                .foregroundStyle(Color.textTertiary)
            Text(change)
                .font(.custom("JetBrains Mono", size: 11))
                .fontWeight(.semibold)
                .foregroundStyle(positive ? Color.semanticGreen : Color.semanticRed)
        }
    }

    private func saveCurrentStep() {
        let stepIndex = currentStepIndex
        switch stepIndex {
        case 6:
            // Save MT5 path (only if the user changed it, so the defaults keep watching
            // both standard MT5 folders) and API key
            if mt5Path != Configuration.mt5PrimaryFolder {
                UserDefaults.standard.set(mt5Path, forKey: Configuration.mt5FolderDefaultsKey)
            }
            if !apiKey.isEmpty {
                KeychainHelper.anthropicAPIKey = apiKey
            }
        default:
            break
        }
        // Persist beginner mode preference from onboarding
        if experience == .beginner {
            UserDefaults.standard.set(true, forKey: "dashboard_beginner_mode")
        }
    }
}
