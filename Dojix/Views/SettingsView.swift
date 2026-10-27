import SwiftUI

struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    @Environment(\.appState) private var appState
    @State private var backup = BackupFlowModel()

    var body: some View {
        Form {
            securitySection
            aiSection
            liveDataSection
            oandaSection
            dataSection
            mt5Section
            aboutSection
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .alert("Delete All Trades?", isPresented: $viewModel.showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                viewModel.deleteAllTrades()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all \(viewModel.tradeCount) imported trades. This cannot be undone.")
        }
        .sheet(isPresented: $viewModel.showSetPasswordSheet) {
            setPasswordSheet
        }
        .sheet(isPresented: $viewModel.showDisableLockSheet) {
            disableLockSheet
        }
        .sheet(isPresented: $backup.showExportSheet) {
            BackupExportSheet(flow: backup) {
                Task { show(await backup.export(from: appState.database)) }
            }
        }
        .sheet(isPresented: $backup.showRestorePasswordSheet) {
            BackupRestorePasswordSheet(flow: backup) {
                Task { show(await backup.restoreWithPassword(into: appState.database)) }
            }
        }
    }

    /// Toast for a finished backup export or restore.
    private func show(_ outcome: BackupFlowModel.Outcome) {
        switch outcome {
        case .none:
            break
        case .success(let message):
            viewModel.loadStats()
            appState.showToast(.success, message)
        case .failure(let message):
            appState.showToast(.error, message)
        }
    }

    // MARK: - AI Section

    private var aiSection: some View {
        Section("AI Analysis") {
            SecureField("Anthropic API Key", text: $viewModel.anthropicAPIKey)
                .textFieldStyle(.roundedBorder)
                .onSubmit { viewModel.saveAnthropicKey() }

            Button {
                viewModel.saveAnthropicKey()
            } label: {
                Label("Save API Key", systemImage: "key")
            }

            HStack(spacing: 4) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(Color.textSecondary)
                    .font(.smallText)
                Text("Stored securely in macOS Keychain")
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
            }

            Text("Optional. AI recommendations in the Edge Report use your own Anthropic API key (create one at console.anthropic.com); usage is billed to your Anthropic account. When you click Run Analysis, a summary of your trade statistics is sent to Anthropic. Individual trades, tickets and notes are never sent. Leave this empty to keep the feature off.")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Live Data Section

    private var liveDataSection: some View {
        Section("Live Market Data") {
            // Data source picker
            Picker("Data Source", selection: $viewModel.liveDataSource) {
                ForEach(LiveDataSource.allCases) { source in
                    Text(source.displayName).tag(source)
                }
            }
            .onChange(of: viewModel.liveDataSource) { viewModel.saveLiveDataSource() }
            Text(viewModel.liveDataSource.description)
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)

            // Connection status + test button
            HStack(spacing: 12) {
                Button {
                    Task { await viewModel.testDataSource() }
                } label: {
                    Label("Test Connection", systemImage: "antenna.radiowaves.left.and.right")
                }
                .disabled(viewModel.isTestingConnection)

                if viewModel.isTestingConnection {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                switch viewModel.dataSourceStatus {
                case .unknown:
                    EmptyView()
                case .ready(let msg):
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.semanticGreen)
                            .font(.smallText)
                        Text(msg)
                            .font(.smallText)
                            .foregroundStyle(Color.semanticGreen)
                    }
                case .error(let msg):
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.semanticRed)
                            .font(.smallText)
                        Text(msg)
                            .font(.smallText)
                            .foregroundStyle(Color.semanticRed)
                    }
                }
            }

            // Contextual fields based on selected source
            switch viewModel.liveDataSource {
            case .twelveDataREST, .twelveDataWebSocket:
                SecureField("Twelve Data API Key", text: $viewModel.twelveDataAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { viewModel.saveTwelveDataKey() }

                Button {
                    viewModel.saveTwelveDataKey()
                } label: {
                    Label("Save API Key", systemImage: "key")
                }

                HStack(spacing: 4) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(Color.textSecondary)
                        .font(.smallText)
                    Text("Stored in macOS Keychain")
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                }

                Text("Get your API key at twelvedata.com. Free tier: 800 req/day. WebSocket requires a paid plan.")
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)

            case .oandaStreaming:
                Text("Configure your OANDA credentials in the OANDA API Import section below.")
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)

            case .polygonWebSocket:
                SecureField("Polygon.io API Key", text: $viewModel.polygonAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { viewModel.savePolygonKey() }

                Button {
                    viewModel.savePolygonKey()
                } label: {
                    Label("Save API Key", systemImage: "key")
                }

                HStack(spacing: 4) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(Color.textSecondary)
                        .font(.smallText)
                    Text("Stored in macOS Keychain")
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                }

                Text("Get your API key at polygon.io. Requires a subscription.")
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)

            case .mt5Direct:
                LabeledContent("Price File") {
                    let commonPath = Configuration.mt5PrimaryFolder
                    let filePath = (commonPath as NSString).appendingPathComponent("DojixPrices.json")
                    let exists = FileManager.default.fileExists(atPath: filePath)

                    HStack(spacing: 4) {
                        Image(systemName: exists ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(exists ? .green : .orange)
                            .font(.smallText)
                        Text(exists ? "Found" : "Not found")
                            .font(.smallText)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                Text("Attach the DojixPriceFeed EA to any chart in MT5. It writes live prices to your Common Files directory — no API key needed. Configure the MT5 path in the MT5 Integration section below.")
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    // MARK: - OANDA Section

    private var oandaSection: some View {
        Section("OANDA API Import") {
            SecureField("API Token", text: $viewModel.oandaToken)
                .textFieldStyle(.roundedBorder)

            TextField("Account ID", text: $viewModel.oandaAccountID)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            Picker("Environment", selection: $viewModel.oandaIsLive) {
                Text("Practice (Demo)").tag(false)
                Text("Live").tag(true)
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
                Button {
                    viewModel.saveOANDACredentials()
                } label: {
                    Label("Save", systemImage: "key")
                }

                Button {
                    Task { await viewModel.testOANDAConnection() }
                } label: {
                    Label("Test Connection", systemImage: "antenna.radiowaves.left.and.right")
                }
                .disabled(viewModel.oandaToken.isEmpty || viewModel.oandaAccountID.isEmpty)
            }

            if let status = viewModel.oandaStatus {
                Text(status)
                    .font(.smallText)
                    .foregroundStyle(status.contains("Connected") ? Color.semanticGreen : .secondary)
            }

            HStack(spacing: 4) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(Color.textSecondary)
                    .font(.smallText)
                Text("Token stored in macOS Keychain")
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
            }

            Text("Get your API token from OANDA's account management portal. Use Practice mode for demo accounts.")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Data Section

    private var dataSection: some View {
        Section("Data") {
            LabeledContent("Imported Trades") {
                Text("\(viewModel.tradeCount)")
                    .font(.system(.body, design: .monospaced))
            }

            LabeledContent("Database Size") {
                Text(BackupService.databaseSize(at: appState.database.databasePath))
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
            }

            HStack(spacing: 12) {
                Button {
                    backup.beginExport(isAppLockOn: viewModel.isAppLockEnabled)
                } label: {
                    Label("Export Backup", systemImage: "arrow.down.doc")
                }

                Button {
                    Task { show(await backup.beginRestore(into: appState.database)) }
                } label: {
                    Label("Restore Backup", systemImage: "arrow.up.doc")
                }
                .disabled(backup.isWorking)
            }
            Text("A backup without a password is not encrypted: anyone who gets the file can read your trades. Use \"Protect this backup with a password\" when exporting.")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)

            HStack(spacing: 12) {
                Button {
                    viewModel.loadSampleTrades()
                } label: {
                    Label("Load Sample Trades", systemImage: "wand.and.stars")
                }
                Button {
                    viewModel.removeSampleTrades()
                } label: {
                    Label("Remove Sample Trades", systemImage: "xmark.bin")
                }
            }
            Text("Sample trades are 30 made-up trades for exploring Dojix. Removing them leaves your own trades untouched.")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)

            Button(role: .destructive) {
                viewModel.showDeleteConfirmation = true
            } label: {
                Label("Delete All Trades", systemImage: "trash")
            }
            .disabled(viewModel.tradeCount == 0)

            if let status = viewModel.statusMessage {
                Text(status)
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    // MARK: - MT5 Section

    private var mt5Section: some View {
        Section("MT5 Integration") {
            LabeledContent("Common Files Path") {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(viewModel.mt5Path)
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)

                    HStack(spacing: 4) {
                        Image(systemName: viewModel.validateMT5Path() ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(viewModel.validateMT5Path() ? .green : .orange)
                            .font(.smallText)
                        Text(viewModel.validateMT5Path() ? "Found" : "Not found")
                            .font(.smallText)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }

            Button {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.message = "Select your MT5 Common Files directory"
                if panel.runModal() == .OK, let url = panel.url {
                    viewModel.mt5Path = url.path
                    appState.startFileWatcher()
                }
            } label: {
                Label("Browse...", systemImage: "folder")
            }
        }
    }

    // MARK: - Security Section

    private var securitySection: some View {
        Section("Security") {
            if viewModel.isAppLockEnabled {
                HStack {
                    Label("App Lock", systemImage: "lock.fill")
                    Spacer()
                    Text("Enabled")
                        .font(.smallText)
                        .foregroundStyle(Color.semanticGreen)
                }

                Button {
                    viewModel.clearPasswordFields()
                    viewModel.showSetPasswordSheet = true
                } label: {
                    Label("Change Password", systemImage: "key.horizontal")
                }

                Picker("Lock when idle", selection: $viewModel.idleLockMinutes) {
                    ForEach(IdleLockSetting.choices, id: \.self) { minutes in
                        Text(IdleLockSetting.title(for: minutes)).tag(minutes)
                    }
                }
                .accessibilityIdentifier("idleLockPicker")

                Button(role: .destructive) {
                    viewModel.clearPasswordFields()
                    viewModel.showDisableLockSheet = true
                } label: {
                    Label("Disable App Lock", systemImage: "lock.open")
                }
            } else {
                HStack {
                    Label("App Lock", systemImage: "lock.open")
                    Spacer()
                    Text("Disabled")
                        .font(.smallText)
                        .foregroundStyle(Color.textSecondary)
                }

                Button {
                    viewModel.clearPasswordFields()
                    viewModel.showSetPasswordSheet = true
                } label: {
                    Label("Enable App Lock", systemImage: "lock.fill")
                }
            }

            Text("With App Lock on, your journal's encryption key is protected by your password: nothing can be decrypted until it is entered. Dojix locks itself after the idle time chosen here (default 15 minutes) with no keyboard or mouse activity in Dojix, and when you hide or minimize it, lock the screen, or the Mac sleeps. There is no recovery; a forgotten password means erasing local data (exported backups still restore).")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private var setPasswordSheet: some View {
        VStack(spacing: 20) {
            Text(viewModel.isAppLockEnabled ? "Change Password" : "Set App Lock Password")
                .font(.headline)

            VStack(spacing: 12) {
                if viewModel.isAppLockEnabled {
                    SecureField("Current Password", text: $viewModel.currentPassword)
                        .textFieldStyle(.roundedBorder)
                }
                SecureField("New Password", text: $viewModel.newPassword)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: viewModel.newPassword) {
                        if viewModel.newPassword.count > 128 {
                            viewModel.newPassword = String(viewModel.newPassword.prefix(128))
                        }
                    }
                SecureField("Confirm Password", text: $viewModel.confirmPassword)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: viewModel.confirmPassword) {
                        if viewModel.confirmPassword.count > 128 {
                            viewModel.confirmPassword = String(viewModel.confirmPassword.prefix(128))
                        }
                    }
            }
            .frame(width: 260)

            if let error = viewModel.passwordError {
                Text(error)
                    .font(.smallText)
                    .foregroundStyle(Color.semanticRed)
            }

            Text("Minimum 8 characters")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)

            HStack(spacing: 12) {
                Button("Cancel") {
                    viewModel.clearPasswordFields()
                    viewModel.showSetPasswordSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Set Password") {
                    Task { await viewModel.setAppLockPassword(appState: appState) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.newPassword.isEmpty || viewModel.confirmPassword.isEmpty || viewModel.isSavingPassword)
            }
        }
        .padding(30)
        .frame(width: 340)
    }

    private var disableLockSheet: some View {
        VStack(spacing: 20) {
            Text("Disable App Lock")
                .font(.headline)

            SecureField("Current Password", text: $viewModel.currentPassword)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)

            if let error = viewModel.passwordError {
                Text(error)
                    .font(.smallText)
                    .foregroundStyle(Color.semanticRed)
            }

            Text("Your journal stays encrypted on disk; its key goes back to your Mac's Keychain without a password.")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("Cancel") {
                    viewModel.clearPasswordFields()
                    viewModel.showDisableLockSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Disable", role: .destructive) {
                    Task { await viewModel.disableAppLock(appState: appState) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.currentPassword.isEmpty || viewModel.isSavingPassword)
            }
        }
        .padding(30)
        .frame(width: 340)
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version") {
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")
            }
            LabeledContent("Build") {
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1")
            }
            LabeledContent("Database") {
                Text("GRDB.swift (SQLite)")
            }
            LabeledContent("License") {
                Text("Free and open source (GPL-3.0)")
            }

            Button {
                appState.onboarding.showTourAgain()
            } label: {
                Label("Show Welcome Tour", systemImage: "sparkles")
            }

            Text("Found a bug or have an idea? Open an issue on the project's GitHub page.")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)
        }
    }
}
