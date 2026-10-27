import XCTest

/// Critical-path UI tests for Dojix v1.0 ship readiness.
/// Option C: automated critical paths + manual visual spot-check.
final class DojixUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = []
        // Keep test runs away from any real journal: private data folder, no MT5 folder.
        let scratch = UITestPaths.scratchRoot + "/dojix-uitests-\(UUID().uuidString)"
        app.launchEnvironment["DOJIX_DATA_DIR"] = scratch + "/data"
        app.launchEnvironment["DOJIX_MT5_DIR"] = scratch + "/mt5"
        if let service = ProcessInfo.processInfo.environment["DOJIX_KEYCHAIN_SERVICE"] {
            app.launchEnvironment["DOJIX_KEYCHAIN_SERVICE"] = service
        }
        // Skip the first-run tour (sets the app's preference for this launch only)
        app.launchArguments += ["-first_onboarding_done", "YES"]
        app.launch()
        // Don't send keystrokes before the main window is up
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Launch

    func testAppLaunchesSuccessfully() throws {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }

    // MARK: - Tab Navigation via Keyboard Shortcuts

    func testNavigateToJournal() throws {
        app.typeKey("1", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.5)
    }

    func testNavigateToDashboard() throws {
        app.typeKey("2", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.5)
    }

    func testNavigateToAnalytics() throws {
        app.typeKey("3", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.5)
    }

    func testNavigateToEdgeReport() throws {
        app.typeKey("4", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.5)
    }

    func testNavigateToPulse() throws {
        app.typeKey("5", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.5)
    }

    func testNavigateToImport() throws {
        app.typeKey("6", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.5)
    }

    func testNavigateToSettings() throws {
        app.typeKey(",", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.5)
        // A control at the top of the Settings screen (Security section). Controls further
        // down a SwiftUI Form may not exist until scrolled into view.
        let settingsControl = app.buttons["Enable App Lock"].firstMatch
        XCTAssertTrue(settingsControl.waitForExistence(timeout: 5))
    }

    // MARK: - Sidebar Click Navigation

    func testSidebarClickNavigation() throws {
        let tabs = ["Journal", "Dashboard", "Analytics",
                    "Edge Report", "Pulse", "Import", "Settings"]

        for tab in tabs {
            let el = app.staticTexts[tab].firstMatch
            if el.waitForExistence(timeout: 3) {
                el.click()
                Thread.sleep(forTimeInterval: 0.3)
            }
        }
    }

    // MARK: - Dashboard Toggle

    func testEssentialAllAnalyticsToggle() throws {
        app.typeKey("2", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.5)

        app.typeKey("e", modifierFlags: [.command, .shift])
        Thread.sleep(forTimeInterval: 0.3)

        app.typeKey("e", modifierFlags: [.command, .shift])
        Thread.sleep(forTimeInterval: 0.3)
    }

    // MARK: - Export Shortcut

    func testExportShortcutDoesNotCrash() throws {
        app.typeKey("1", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.3)
        app.typeKey("e", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.5)
        // Export is available to everyone now, so a save panel opens: dismiss it
        app.typeKey(.escape, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 3))
    }
}
