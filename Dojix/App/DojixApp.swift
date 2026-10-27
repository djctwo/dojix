import SwiftUI
import GRDB
import os

@main
struct DojixApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.isDatabaseFailed {
                    DatabaseFailedView(errorMessage: appState.databaseError ?? "Unknown error")
                } else if let olderJournal = appState.olderJournal {
                    OlderJournalView(prompt: olderJournal)
                } else if appState.isLocked {
                    LockScreenView()
                } else if appState.onboarding.isOnboardingComplete {
                    ContentView()
                        .frame(minWidth: 900, minHeight: 600)
                        .onAppear {
                            appState.startFileWatcher()
                        }
                        .task {
                            await appState.loadSidebarQuotes()
                        }
                        .alert("Database Issue", isPresented: .init(
                            get: { appState.databaseError != nil && !appState.isDatabaseFailed },
                            set: { if !$0 { appState.databaseError = nil } }
                        )) {
                            Button("OK", role: .cancel) { }
                        } message: {
                            Text(appState.databaseError ?? "")
                        }
                } else {
                    OnboardingView(isFirstTime: appState.onboarding.isFirstOnboarding)
                }
            }
            .environment(\.appState, appState)
            .onChange(of: scenePhase) { _, newPhase in
                // Auto-lock when app goes to background (if app lock is enabled): the
                // journal is saved and wiped from memory until the password is entered.
                if newPhase == .background {
                    appState.lock()
                }
            }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1200, height: 800)
        .commands {
            // Navigation shortcuts
            CommandGroup(replacing: .sidebar) {
                Button("Show Journal") {
                    appState.selectedTab = .journal
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Show Dashboard") {
                    appState.selectedTab = .dashboard
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Show Analytics") {
                    appState.selectedTab = .analytics
                }
                .keyboardShortcut("3", modifiers: .command)

                Button("Show Edge Report") {
                    appState.selectedTab = .edgeReport
                }
                .keyboardShortcut("4", modifiers: .command)

                Button("Show Pulse") {
                    appState.selectedTab = .pulse
                }
                .keyboardShortcut("5", modifiers: .command)

                Button("Show Import") {
                    appState.selectedTab = .importTrades
                }
                .keyboardShortcut("6", modifiers: .command)

                Button("Show Settings") {
                    appState.selectedTab = .settings
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            // View shortcuts
            CommandGroup(after: .sidebar) {
                Divider()
                Button("Toggle Essential/All Analytics") {
                    let current = UserDefaults.standard.bool(forKey: "dashboard_beginner_mode")
                    UserDefaults.standard.set(!current, forKey: "dashboard_beginner_mode")
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }

            // File menu — export
            CommandGroup(after: .saveItem) {
                Button("Export PDF...") {
                    NotificationCenter.default.post(name: .exportPDF, object: nil)
                }
                .keyboardShortcut("e", modifiers: .command)
            }

            // Help menu
            CommandGroup(replacing: .help) {
                Button("Dojix Help") {
                    openHelpWindow()
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }

        // About window
        Window("About Dojix", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)

        // Help window
        Window("Dojix Help", id: "help") {
            HelpView()
        }
        .defaultSize(width: 900, height: 600)
    }

    @Environment(\.openWindow) private var openWindow

    private func openHelpWindow() {
        openWindow(id: "help")
    }
}

// MARK: - Notifications

extension Notification.Name {
    /// Posted by the File > Export PDF menu command (Cmd+E)
    static let exportPDF = Notification.Name("exportPDF")
}

// MARK: - App Delegate

/// Runs shutdown work synchronously before the process exits. App-level (not tied to
/// a window), so it also runs when Dojix quits with no window open.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Locks on screen lock, sleep, user switch, hide and minimize (when App Lock is on).
    private var autoLock: AutoLockMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let monitor = AutoLockMonitor { AppState.shared.lock() }
        // Idle lock: while the journal is open, including while a sheet, alert, menu or
        // open/save panel is up (the timer runs in the common run-loop modes; locking
        // closes those). `lock()` itself does nothing when App Lock is off.
        monitor.startIdleTracking(IdleLockTimer(isTracking: {
            let state = AppState.shared
            return !state.isLocked && state.olderJournal == nil && !state.isDatabaseFailed
        }, lock: { AppState.shared.lock() }))
        autoLock = monitor
    }

    func applicationWillTerminate(_ notification: Notification) {
        // The journal is saved (encrypted) after every change; this writes the last state
        // and waits for any save still in flight.
        AppState.shared.database.saveForShutdown()
    }
}
