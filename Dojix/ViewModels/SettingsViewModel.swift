import Foundation
import os

/// ViewModel for the Settings view
@Observable
@MainActor
final class SettingsViewModel {
    private let repository: TradeRepository
    private nonisolated static let logger = Logger(subsystem: "com.dojix", category: "SettingsVM")

    /// MT5 folder to watch; saved immediately when changed so the watcher uses it
    var mt5Path: String = Configuration.mt5PrimaryFolder {
        didSet {
            guard mt5Path != oldValue else { return }
            UserDefaults.standard.set(mt5Path, forKey: Configuration.mt5FolderDefaultsKey)
        }
    }
    var anthropicAPIKey: String = ""
    var twelveDataAPIKey: String = ""
    var tradeCount: Int = 0
    var showDeleteConfirmation = false
    var statusMessage: String?

    // Live data
    var polygonAPIKey: String = ""
    var liveDataSource: LiveDataSource = .twelveDataREST
    var dataSourceStatus: DataSourceStatus = .unknown
    var isTestingConnection = false

    enum DataSourceStatus: Equatable {
        case unknown
        case ready(String)
        case error(String)

        var isReady: Bool {
            if case .ready = self { return true }
            return false
        }
    }

    // OANDA
    var oandaToken: String = ""
    var oandaAccountID: String = ""
    var oandaIsLive: Bool = false
    var oandaStatus: String?

    // App lock
    var isAppLockEnabled: Bool = false
    var currentPassword: String = ""
    var newPassword: String = ""
    var confirmPassword: String = ""
    var showSetPasswordSheet = false
    var showDisableLockSheet = false
    var isSavingPassword = false
    var passwordError: String?
    /// "Lock when idle" (App Lock on): minutes without activity, 0 = Off.
    var idleLockMinutes: Int = IdleLockSetting.minutes() {
        didSet { IdleLockSetting.set(idleLockMinutes) }
    }

    /// Back-off for wrong current passwords (shared with the lock screen).
    private let throttle: UnlockThrottle

    init(repository: TradeRepository, throttle: UnlockThrottle = .shared) {
        self.repository = repository
        self.throttle = throttle
        // Migrate from UserDefaults to Keychain on first access
        KeychainHelper.migrateFromUserDefaults()
        self.anthropicAPIKey = KeychainHelper.anthropicAPIKey ?? ""
        self.twelveDataAPIKey = KeychainHelper.twelveDataAPIKey ?? ""
        self.polygonAPIKey = KeychainHelper.polygonAPIKey ?? ""
        self.liveDataSource = KeychainHelper.liveDataSource
        self.oandaToken = KeychainHelper.oandaAPIToken ?? ""
        self.oandaAccountID = KeychainHelper.oandaAccountID ?? ""
        self.oandaIsLive = KeychainHelper.oandaIsLive
        self.isAppLockEnabled = AppLock.isEnabled()
        loadStats()
    }

    func saveAnthropicKey() {
        KeychainHelper.anthropicAPIKey = anthropicAPIKey
        statusMessage = "Anthropic API key saved securely"
    }

    func saveTwelveDataKey() {
        KeychainHelper.twelveDataAPIKey = twelveDataAPIKey
        statusMessage = "Twelve Data API key saved securely"
    }

    func savePolygonKey() {
        KeychainHelper.polygonAPIKey = polygonAPIKey
        statusMessage = "Polygon.io API key saved securely"
    }

    func saveLiveDataSource() {
        KeychainHelper.liveDataSource = liveDataSource
        statusMessage = "Live data source changed to \(liveDataSource.displayName)"
        dataSourceStatus = .unknown
    }

    /// Test whether the selected data source is configured and reachable
    func testDataSource() async {
        isTestingConnection = true
        dataSourceStatus = .unknown

        switch liveDataSource {
        case .twelveDataREST, .twelveDataWebSocket:
            guard let key = KeychainHelper.twelveDataAPIKey, !key.isEmpty else {
                dataSourceStatus = .error("No API key configured")
                isTestingConnection = false
                return
            }
            do {
                let service = TwelveDataService(apiKey: key)
                let quotes = try await service.getQuotes(symbols: ["EUR/USD"])
                if quotes.isEmpty {
                    dataSourceStatus = .error("API returned no data")
                } else {
                    dataSourceStatus = .ready("Connected — EUR/USD: \(String(format: "%.5f", quotes[0].close))")
                }
            } catch {
                dataSourceStatus = .error(error.localizedDescription)
            }

        case .oandaStreaming:
            guard let token = KeychainHelper.oandaAPIToken, !token.isEmpty,
                  let accountId = KeychainHelper.oandaAccountID, OANDAService.isValidAccountID(accountId) else {
                dataSourceStatus = .error("OANDA credentials not configured (account ID: letters, digits and dashes only)")
                isTestingConnection = false
                return
            }
            // Quick REST check against OANDA pricing endpoint
            let baseURL = KeychainHelper.oandaIsLive
                ? "https://api-fxtrade.oanda.com"
                : "https://api-fxpractice.oanda.com"
            guard let url = URL(string: "\(baseURL)/v3/accounts/\(accountId)/pricing?instruments=EUR_USD") else {
                dataSourceStatus = .error("Invalid URL")
                isTestingConnection = false
                return
            }
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            do {
                let session = SecureSession.make(timeout: 15)
                let (_, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    dataSourceStatus = .ready("Connected to OANDA \(KeychainHelper.oandaIsLive ? "Live" : "Practice")")
                } else {
                    dataSourceStatus = .error("OANDA returned error")
                }
            } catch {
                dataSourceStatus = .error(error.localizedDescription)
            }

        case .polygonWebSocket:
            guard let key = KeychainHelper.polygonAPIKey, !key.isEmpty else {
                dataSourceStatus = .error("No API key configured")
                isTestingConnection = false
                return
            }
            // Quick REST check against Polygon (key in header, not query param)
            guard let url = URL(string: "https://api.polygon.io/v2/last/nbbo/C:EURUSD") else {
                dataSourceStatus = .error("Invalid URL")
                isTestingConnection = false
                return
            }
            var polygonRequest = URLRequest(url: url, timeoutInterval: 15)
            polygonRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            do {
                let session = SecureSession.make(timeout: 15)
                let (_, response) = try await session.data(for: polygonRequest)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    dataSourceStatus = .ready("Connected to Polygon.io")
                } else if let http = response as? HTTPURLResponse, http.statusCode == 403 {
                    dataSourceStatus = .error("Invalid API key")
                } else {
                    dataSourceStatus = .error("Polygon returned error")
                }
            } catch {
                dataSourceStatus = .error(error.localizedDescription)
            }

        case .mt5Direct:
            let path = Configuration.mt5PrimaryFolder
            let filePath = (path as NSString).appendingPathComponent("DojixPrices.json")
            // Single I/O call — attributesOfItem fails if file doesn't exist
            if let attrs = try? FileManager.default.attributesOfItem(atPath: filePath),
               let modified = attrs[.modificationDate] as? Date {
                let age = Date().timeIntervalSince(modified)
                if age < 10 {
                    dataSourceStatus = .ready("Receiving prices (updated \(Int(saturating: age))s ago)")
                } else if age < 60 {
                    dataSourceStatus = .ready("File found (last update \(Int(saturating: age))s ago)")
                } else {
                    dataSourceStatus = .error("File stale — last update \(Int(saturating: age / 60))m ago. Is the EA running?")
                }
            } else {
                dataSourceStatus = .error("DojixPrices.json not found. Attach DojixPriceFeed EA in MT5.")
            }
        }

        isTestingConnection = false
    }

    func loadStats() {
        do {
            tradeCount = try repository.count()
        } catch {
            Self.logger.error("Failed to load stats: \(error.localizedDescription)")
        }
    }

    /// Add the 30 fictional sample trades (skips any already present)
    func loadSampleTrades() {
        do {
            let added = try repository.bulkInsert(DemoDataGenerator.generateTrades())
            loadStats()
            statusMessage = added > 0 ? "Added \(added) fictional sample trades" : "Sample trades are already loaded"
        } catch {
            statusMessage = "Couldn't add sample trades: \(error.localizedDescription)"
        }
    }

    /// Remove only the fictional sample trades
    func removeSampleTrades() {
        do {
            let removed = try repository.deleteSampleTrades()
            loadStats()
            statusMessage = "Removed \(removed) sample trades"
        } catch {
            statusMessage = "Couldn't remove sample trades: \(error.localizedDescription)"
        }
    }

    func deleteAllTrades() {
        do {
            try repository.deleteAll()
            tradeCount = 0
            statusMessage = "All trades deleted"
            Self.logger.info("All trades deleted by user")
        } catch {
            statusMessage = "Failed to delete: \(error.localizedDescription)"
        }
    }

    // MARK: - OANDA

    func saveOANDACredentials() {
        oandaToken = oandaToken.trimmingCharacters(in: .whitespacesAndNewlines)
        oandaAccountID = oandaAccountID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard oandaAccountID.isEmpty || OANDAService.isValidAccountID(oandaAccountID) else {
            oandaStatus = "Account ID can only contain letters, digits and dashes"
            return
        }
        KeychainHelper.oandaAPIToken = oandaToken
        KeychainHelper.oandaAccountID = oandaAccountID
        KeychainHelper.oandaIsLive = oandaIsLive
        oandaStatus = "OANDA credentials saved"
    }

    func testOANDAConnection() async {
        guard !oandaToken.isEmpty, !oandaAccountID.isEmpty else {
            oandaStatus = "Enter API token and account ID first"
            return
        }

        saveOANDACredentials()
        let service = OANDAService(apiToken: oandaToken, accountID: oandaAccountID, isLive: oandaIsLive)
        do {
            let summary = try await service.fetchAccountSummary()
            oandaStatus = "Connected — \(summary.currency) account, balance: \(summary.balance)"
        } catch {
            oandaStatus = error.localizedDescription
        }
    }

    func validateMT5Path() -> Bool {
        FileManager.default.fileExists(atPath: mt5Path)
    }

    // MARK: - App Lock

    /// Enable App Lock, or change its password (then `currentPassword` is required and
    /// wrong guesses are throttled like on the lock screen). The database key is wrapped
    /// with the new password. Once the new password is stored the change is reported as
    /// made, and the lock state shown is always re-read afterwards.
    func setAppLockPassword(appState: any AppLockActions) async {
        if let problem = PasswordRules.problem(password: newPassword, confirmation: confirmPassword) {
            passwordError = problem
            return
        }
        let isChanging = isAppLockEnabled
        if isChanging, currentPassword.isEmpty {
            passwordError = "Enter your current password"
            return
        }
        if isChanging, let wait = throttle.lockoutMessage() {
            passwordError = wait
            return
        }

        isSavingPassword = true
        defer {
            isSavingPassword = false
            isAppLockEnabled = appState.isAppLockOn
        }
        do {
            let outcome: KeyRotation.Outcome
            if isChanging {
                outcome = try await appState.changeAppLockPassword(current: currentPassword, new: newPassword)
                throttle.reset()
            } else {
                outcome = try await appState.enableAppLock(password: newPassword)
            }
            let done = isChanging ? "App lock password changed" : "App lock enabled"
            statusMessage = outcome == .complete ? done
                : "\(done). Dojix will finish re-encrypting your files the next time you unlock."
            clearPasswordFields()
            showSetPasswordSheet = false
        } catch DatabaseKeyVault.VaultError.wrongPassword where isChanging {
            passwordError = wrongPasswordMessage()
        } catch {
            passwordError = error.localizedDescription
        }
    }

    /// Disable App Lock after confirming the current password (throttled like the lock screen).
    func disableAppLock(appState: any AppLockActions) async {
        guard !currentPassword.isEmpty else {
            passwordError = "Enter your current password"
            return
        }
        if let wait = throttle.lockoutMessage() {
            passwordError = wait
            return
        }
        isSavingPassword = true
        defer {
            isSavingPassword = false
            isAppLockEnabled = appState.isAppLockOn
        }
        do {
            try await appState.disableAppLock(password: currentPassword)
            throttle.reset()
            clearPasswordFields()
            showDisableLockSheet = false
            statusMessage = "App lock disabled"
        } catch DatabaseKeyVault.VaultError.wrongPassword {
            passwordError = wrongPasswordMessage()
        } catch {
            passwordError = error.localizedDescription
        }
    }

    /// Count a wrong current password (shared back-off with the lock screen).
    private func wrongPasswordMessage() -> String {
        let message = throttle.recordFailure()
        return message.hasPrefix("Incorrect password") ? "Current password is incorrect" : message
    }

    func clearPasswordFields() {
        currentPassword = ""
        newPassword = ""
        confirmPassword = ""
        passwordError = nil
    }

}
