import SwiftUI

struct ContentView: View {
    @Environment(\.appState) private var appState

    // Persist ViewModels across tab switches
    @State private var journalVM: JournalViewModel?
    @State private var dashboardVM: DashboardViewModel?
    @State private var edgeReportVM: EdgeReportViewModel?
    @State private var settingsVM: SettingsViewModel?
    @State private var importVM: ImportViewModel?

    var body: some View {
        @Bindable var appState = appState
        NavigationSplitView {
            SidebarView(selectedTab: $appState.selectedTab)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.bgContent)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 8))
        }
        .navigationSplitViewStyle(.balanced)
        .toast($appState.toast)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var detailView: some View {
        switch appState.selectedTab {
        case .journal:
            JournalView(viewModel: getJournalVM())
        case .dashboard:
            DashboardView(viewModel: getDashboardVM(), category: .overview)
        case .analytics:
            AnalyticsContainerView(viewModel: getDashboardVM())
        case .edgeReport:
            EdgeReportView(viewModel: getEdgeReportVM())
        case .pulse:
            PulseView()
        case .importTrades:
            ImportView(viewModel: getImportVM())
        case .settings:
            SettingsView(viewModel: getSettingsVM())
        }
    }

    // MARK: - Lazy ViewModel Accessors

    private func getJournalVM() -> JournalViewModel {
        if let vm = journalVM { return vm }
        let vm = JournalViewModel(
            repository: appState.tradeRepository,
            database: appState.database
        )
        DispatchQueue.main.async { journalVM = vm }
        return vm
    }

    private func getDashboardVM() -> DashboardViewModel {
        if let vm = dashboardVM { return vm }
        let vm = DashboardViewModel(
            repository: appState.tradeRepository,
            database: appState.database
        )
        DispatchQueue.main.async { dashboardVM = vm }
        return vm
    }

    private func getEdgeReportVM() -> EdgeReportViewModel {
        if let vm = edgeReportVM { return vm }
        let vm = EdgeReportViewModel(
            repository: appState.tradeRepository,
            database: appState.database
        )
        DispatchQueue.main.async { edgeReportVM = vm }
        return vm
    }

    private func getSettingsVM() -> SettingsViewModel {
        if let vm = settingsVM { return vm }
        let vm = SettingsViewModel(
            repository: appState.tradeRepository
        )
        DispatchQueue.main.async { settingsVM = vm }
        return vm
    }

    private func getImportVM() -> ImportViewModel {
        if let vm = importVM { return vm }
        let vm = ImportViewModel(
            importer: SAImporter(repository: appState.tradeRepository),
            repository: appState.tradeRepository
        )
        vm.onImportSuccess = {
            appState.showToast(.success, "Trades imported successfully")
            let totalTrades = (try? appState.tradeRepository.count()) ?? 0
            if totalTrades >= 10 && !UserDefaults.standard.bool(forKey: "has_seen_first_look") {
                UserDefaults.standard.set(true, forKey: "dashboard_beginner_mode")
                UserDefaults.standard.set(true, forKey: "show_first_look_banner")
            }
            appState.selectedTab = .dashboard
        }
        DispatchQueue.main.async { importVM = vm }
        return vm
    }
}
