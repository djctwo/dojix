import SwiftUI
import GRDB
import os

/// Global app state injected via @Environment
@Observable
final class AppState {
    let database: DatabaseManager
    let tradeRepository: TradeRepository
    let onboarding: OnboardingManager
    private var fileWatchers: [FileWatcher] = []
    static let logger = Logger(subsystem: "com.dojix", category: "AppState")

    var selectedTab: SidebarTab = .journal
    var autoImportCount: Int = 0
    var databaseError: String?
    var toast: ToastData?

    /// App is in an unrecoverable state — database failed even after recovery.
    /// When true, DatabaseFailedView is shown and no features are accessible.
    var isDatabaseFailed: Bool = false

    /// App lock state — true when app is locked and awaiting password
    var isLocked: Bool = false

    /// Whether App Lock is set. Kept in memory (set at launch, on unlock, enable and
    /// disable) so that locking never depends on reading the Keychain at that moment.
    var isAppLockOn: Bool = false

    /// Enable App Lock or an unlock is running: a lock requested meanwhile is remembered
    /// and carried out when it ends (see `AppState+KeyOperations`).
    @ObservationIgnored var lockDeferrals = 0
    @ObservationIgnored var isLockRequestedMeanwhile = false

    /// Key operations running (unlock, Enable / Change Password / Disable App Lock);
    /// "Erase Everything" waits for them, so none can store a key over the new one.
    @ObservationIgnored var keyOperationsInFlight = 0
    @ObservationIgnored var keyOperationWaiters: [CheckedContinuation<Void, Never>] = []
    /// An unlock is running: a second one (another window) is refused, not run alongside.
    @ObservationIgnored var isUnlocking = false

    /// This copy's hold on the data folder (see `InstanceLock`), kept while it runs.
    @ObservationIgnored var instanceLock: InstanceLock?

    /// Set when the journal file is older than the last one this Mac saved (rollback
    /// protection): the journal stays closed until the user opens it anyway or cancels.
    var olderJournal: OlderJournalPrompt?

    /// Shared live quotes for sidebar ticker (written by PulseViewModel or app launch)
    var sidebarQuotes: [TwelveDataService.Quote] = []

    /// The single app-wide instance (one database per process).
    /// Mutated only from the main thread by SwiftUI views.
    nonisolated(unsafe) static let shared = AppState()

    /// Show a toast notification
    func showToast(_ style: ToastStyle, _ message: String) {
        toast = ToastData(style: style, message: message)
    }

    /// Holds the database key (wrapped with the App Lock password when the lock is on).
    let vault: DatabaseKeyVault

    /// Test seams (all nil in the app).
    @ObservationIgnored var hooks = Hooks()

    struct Hooks {
        /// Runs off the main actor in the middle of Enable / Change Password / Disable
        /// App Lock: after the password check, before the Keychain is changed.
        var whileChangingKey: (@Sendable () async -> Void)?
        /// Runs off the main actor in the middle of an unlock, after the password was
        /// checked and before the journal is opened.
        var whileUnlocking: (@Sendable () async -> Void)?
    }

    /// Screenshot files (sealed with the database key).
    let screenshots: ScreenshotManager

    init() {
        self.onboarding = OnboardingManager()
        self.vault = DatabaseKeyVault()
        self.screenshots = .shared
        KeychainHelper.migrateFromUserDefaults()
        do {
            // Nothing is read from disk here: the journal stays closed (and encrypted)
            // until `startUp()` opens it, which needs the key, which needs the App Lock
            // password when the lock is on.
            self.database = try DatabaseManager()
            self.tradeRepository = TradeRepository(database: database)
        } catch {
            Self.logger.critical("Database setup failed: \(error.localizedDescription)")
            // Fallback to in-memory database so app doesn't crash.
            // isDatabaseFailed blocks UI — user sees DatabaseFailedView, not the app.
            // Safe: DatabaseManager(inMemory: true) cannot fail for the same reasons as file-backed.
            self.database = try! DatabaseManager(inMemory: true) // swiftlint:disable:this force_try
            self.tradeRepository = TradeRepository(database: database)
            self.isDatabaseFailed = true
            self.databaseError = "Dojix cannot start due to a database error. Please restart the app."
            return
        }
        startUp(instanceLockDirectory: Configuration.dataDirectory)
    }

    /// For tests: a journal at a scratch path, an injected key vault (no Keychain) and,
    /// optionally, the folder whose single-instance lock this copy must hold.
    init(database: DatabaseManager, vault: DatabaseKeyVault, screenshotsDirectory: URL,
         instanceLockDirectory: URL? = nil) {
        self.onboarding = OnboardingManager()
        self.vault = vault
        self.screenshots = ScreenshotManager(baseDir: screenshotsDirectory, keyProvider: { [database] in database.currentKey })
        self.database = database
        self.tradeRepository = TradeRepository(database: database)
        startUp(instanceLockDirectory: instanceLockDirectory)
    }

    /// The folder holding the journal (shown in messages).
    var dataFolderPath: String { URL(fileURLWithPath: database.databasePath).deletingLastPathComponent().path }

    /// Move an unreadable database out of the way so a fresh one can be created.
    /// The old file is renamed, not deleted, so no data is ever destroyed here.
    /// Returns the new file name, or nil if there was nothing to move.
    func moveAsideUnreadableDatabase() -> String? {
        let fileManager = FileManager.default
        let dbURL = URL(fileURLWithPath: database.databasePath)
        let dir = dbURL.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: dbURL.path) else { return nil }
        let stamp = Int(saturating: Date().timeIntervalSince1970)
        let keptName = "\(dbURL.lastPathComponent).unreadable-\(stamp)"
        do {
            try fileManager.moveItem(at: dbURL, to: dir.appendingPathComponent(keptName))
            for suffix in ["-wal", "-shm"] {
                let side = URL(fileURLWithPath: dbURL.path + suffix)
                if fileManager.fileExists(atPath: side.path) {
                    try? fileManager.moveItem(at: side, to: dir.appendingPathComponent(keptName + suffix))
                }
            }
            Self.logger.info("Moved unreadable database aside as \(keptName)")
            return keptName
        } catch {
            Self.logger.error("Could not move unreadable database aside: \(error.localizedDescription)")
            return nil
        }
    }

    /// Watch the MT5 folder(s) for new or updated StrategyAnalytics CSV files
    func startFileWatcher() {
        stopFileWatcher()
        let repo = tradeRepository
        let existing = Configuration.mt5WatchFolders.filter { FileManager.default.fileExists(atPath: $0) }
        fileWatchers = existing.map { folder in
            FileWatcher(path: folder) { path in
                let importer = SAImporter(repository: repo)
                Task { @MainActor in
                    _ = await importer.importFile(at: path)
                }
            }
        }
        fileWatchers.forEach { $0.start() }
    }

    /// Stop the file watchers
    func stopFileWatcher() {
        fileWatchers.forEach { $0.stop() }
        fileWatchers = []
    }

    /// Load initial quotes for sidebar ticker (non-blocking)
    @MainActor
    func loadSidebarQuotes() async {
        guard let apiKey = KeychainHelper.twelveDataAPIKey, !apiKey.isEmpty else {
            Self.logger.warning("No Twelve Data API key — sidebar quotes skipped")
            return
        }
        let defaultPairs = ["EUR/USD", "GBP/USD", "USD/JPY", "AUD/USD", "GBP/JPY"]
        let pairs = UserDefaults.standard.stringArray(forKey: "watchlist_pairs") ?? defaultPairs
        let service = TwelveDataService(apiKey: apiKey)
        do {
            let quotes = try await service.getQuotes(symbols: pairs)
            sidebarQuotes = quotes
            Self.logger.info("Sidebar quotes loaded: \(quotes.count) pairs")
        } catch {
            Self.logger.error("Sidebar quotes failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Environment Key

extension EnvironmentValues {
    // The default must be the one shared instance. A fresh AppState() here was built
    // every time a view outside the main window read the environment, opening extra
    // database connections that blocked the shutdown checkpoint and encryption.
    @Entry var appState: AppState = AppState.shared
}

enum SidebarTab: String, CaseIterable, Identifiable {
    // Core
    case journal = "Journal"
    case dashboard = "Dashboard"
    case analytics = "Analytics"
    // Tools
    case edgeReport = "Edge Report"
    case pulse = "Pulse"
    case importTrades = "Import"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .journal: "list.bullet.rectangle"
        case .dashboard: "chart.bar.xaxis"
        case .analytics: "chart.xyaxis.line"
        case .edgeReport: "target"
        case .pulse: "waveform.path.ecg"
        case .importTrades: "square.and.arrow.down"
        case .settings: "gearshape"
        }
    }

    /// Lucide SVG icon name from asset catalog
    var lucideIcon: String {
        switch self {
        case .journal: "icon-journal"
        case .dashboard: "icon-dashboard"
        case .analytics: "icon-performance"
        case .edgeReport: "icon-edge-report"
        case .pulse: "icon-pulse"
        case .importTrades: "icon-import"
        case .settings: "icon-settings"
        }
    }

    /// Sidebar section grouping
    enum Section: String, CaseIterable {
        case core = "Core"
        case tools = "Tools"
    }

    var section: Section {
        switch self {
        case .journal, .dashboard, .analytics: .core
        case .edgeReport, .pulse, .importTrades, .settings: .tools
        }
    }

    /// Tabs for each section, in display order
    static func tabs(for section: Section) -> [SidebarTab] {
        allCases.filter { $0.section == section }
    }
}
