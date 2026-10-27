import Foundation

/// App-wide constants and configuration
enum Configuration {
    /// Database filename
    static let databaseFilename = "Dojix.sqlite"

    // MARK: - Storage Isolation

    /// Bundle identifier of the official build. Its data lives in
    /// ~/Library/Application Support/Dojix and its Keychain service is this ID.
    static let productionBundleIdentifier = "com.dojix.app"

    /// Bundle identifier of the running build (falls back to the official ID).
    static let bundleIdentifier = Bundle.main.bundleIdentifier ?? productionBundleIdentifier

    /// Whether the `DOJIX_*` environment overrides (data folder, Keychain service, MT5
    /// folder) are honoured. Only in Debug builds (development, unit and UI tests): a
    /// Release build ignores them, so nobody can point an installed Dojix at another
    /// folder (for example a copy of your encrypted journal) with an environment variable.
    #if DEBUG
    static let allowsEnvironmentOverrides = true
    #else
    static let allowsEnvironmentOverrides = false
    #endif

    /// The value of a development override, or nil when overrides are not allowed.
    static func environmentOverride(
        _ name: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        allowed: Bool = allowsEnvironmentOverrides
    ) -> String? {
        guard allowed, let value = environment[name], !value.isEmpty else { return nil }
        return value
    }

    /// Keychain service name. Tied to the bundle ID so a development or test build
    /// (for example `com.dojix.app.dev`) can never read or overwrite the Keychain
    /// items (API keys, database key, app-lock password) of the official app.
    /// Debug builds with a non-official bundle ID may set `DOJIX_KEYCHAIN_SERVICE` to use a
    /// throwaway service name (ad-hoc signed rebuilds otherwise trigger macOS Keychain
    /// prompts for items saved by the previous build). Release builds ignore it.
    static let keychainService: String = {
        if bundleIdentifier != productionBundleIdentifier,
           let override = environmentOverride("DOJIX_KEYCHAIN_SERVICE") {
            return override
        }
        return bundleIdentifier
    }()

    /// Folder that holds the database and screenshots.
    /// - `DOJIX_DATA_DIR` environment variable (Debug builds only; tests and screenshots).
    /// - Official build: ~/Library/Application Support/Dojix
    /// - Any other bundle ID: ~/Library/Application Support/Dojix-<bundle id>
    static var dataDirectory: URL {
        if let override = environmentOverride("DOJIX_DATA_DIR") {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = bundleIdentifier == productionBundleIdentifier ? "Dojix" : "Dojix-\(bundleIdentifier)"
        return appSupport.appendingPathComponent(folder, isDirectory: true)
    }

    // MARK: - MetaTrader 5

    /// Optional override for both MT5 folders (`DOJIX_MT5_DIR`, Debug builds only), used by
    /// tests so a development build never auto-imports files from a real MT5 install.
    private static let mt5Override: String? = {
        guard let value = environmentOverride("DOJIX_MT5_DIR") else { return nil }
        return (value as NSString).expandingTildeInPath
    }()

    /// MT5 terminal-specific MQL5/Files path (where SA CSV is written without FILE_COMMON)
    static let mt5CommonFilesPath = mt5Override ?? NSString(
        string: "~/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5/Files/"
    ).expandingTildeInPath

    /// MT5 Common Files path (where FILE_COMMON flag writes — used by the price-feed EA)
    static let mt5FileCommonPath = mt5Override ?? NSString(
        string: "~/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files/"
    ).expandingTildeInPath

    /// UserDefaults key for the MT5 folder the user picked (Settings / onboarding)
    static let mt5FolderDefaultsKey = "mt5_common_path"

    /// Folders to watch for StrategyAnalytics CSVs and to read the price feed from:
    /// the folder the user chose, or else MT5's shared Common Files folder (where
    /// scripts using FILE_COMMON write) plus the terminal's own MQL5/Files folder.
    static var mt5WatchFolders: [String] {
        if let mt5Override { return [mt5Override] }
        if let saved = UserDefaults.standard.string(forKey: mt5FolderDefaultsKey), !saved.isEmpty {
            return [(saved as NSString).expandingTildeInPath]
        }
        return [mt5FileCommonPath, mt5CommonFilesPath]
    }

    /// Primary MT5 folder (first of `mt5WatchFolders`), used for the price feed and pickers
    static var mt5PrimaryFolder: String {
        mt5WatchFolders.first ?? mt5FileCommonPath
    }

    /// SA CSV filename pattern
    static let saCSVPattern = "StrategyAnalytics_Results_"

    /// SA CSV date format in filenames
    static let saFilenameDateFormat = "yyyyMMdd"

    /// SA CSV datetime format in data
    static let saDateTimeFormat = "yyyy.MM.dd HH:mm:ss"

    /// Minimum trades before generating recommendations
    static let minimumTradesForAnalysis = 30

    /// Session definitions (UTC hours)
    enum Session {
        static let asianStart = 0
        static let asianEnd = 9
        static let londonStart = 7
        static let londonEnd = 16
        static let newYorkStart = 12
        static let newYorkEnd = 21
    }
}
