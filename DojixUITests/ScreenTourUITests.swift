import XCTest

/// Loads the fictional sample trades and walks every main screen: no crash,
/// no paywall or upgrade text, and optional features show an "add your own key"
/// state. Each screen is attached to the test result as a screenshot (CI exports them).
final class ScreenTourUITests: XCTestCase {

    private var app: XCUIApplication!
    private let env = ProcessInfo.processInfo.environment

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        let scratch = UITestPaths.scratchRoot + "/dojix-uitests-tour-\(UUID().uuidString)"
        app.launchEnvironment["DOJIX_DATA_DIR"] = scratch + "/data"
        app.launchEnvironment["DOJIX_MT5_DIR"] = scratch + "/mt5"
        if let service = env["DOJIX_KEYCHAIN_SERVICE"] {
            app.launchEnvironment["DOJIX_KEYCHAIN_SERVICE"] = service
        }
        app.launchArguments += ["-first_onboarding_done", "YES", "-has_seen_first_look", "YES"]
        app.launch()
        // Don't send keystrokes before the main window is up
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
    }

    func testWalkEveryScreenWithSampleData() throws {
        // Settings: load the sample trades
        app.typeKey(",", modifierFlags: .command)
        let load = app.buttons["Load Sample Trades"].firstMatch
        XCTAssertTrue(load.waitForExistence(timeout: 5))
        load.click()
        XCTAssertTrue(app.staticTexts["Added 30 fictional sample trades"].waitForExistence(timeout: 5))
        snapshot("settings")

        let screens: [(key: String, name: String)] = [
            ("1", "journal"), ("2", "dashboard"), ("3", "analytics"),
            ("4", "edge-report"), ("5", "pulse"), ("6", "import"),
        ]
        for screen in screens {
            app.typeKey(screen.key, modifierFlags: .command)
            Thread.sleep(forTimeInterval: 1.5)
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 3), "\(screen.name) crashed the app")
            assertNoPaywall(on: screen.name)
            snapshot(screen.name)
        }

        // Edge Report: AI is opt-in and asks for the user's own key
        app.typeKey("4", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Add Your API Key"].waitForExistence(timeout: 3),
                      "Edge Report should offer to add your own key")

        // Help window opens
        app.typeKey("?", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 3))
    }

    private func assertNoPaywall(on screen: String) {
        for word in ["Upgrade", "Pro+", "Trial", "Subscription", "per month", "/mo"] {
            let matches = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", word))
            XCTAssertEqual(matches.count, 0, "'\(word)' shown on \(screen)")
        }
    }

    private func snapshot(_ name: String) {
        let shot = app.windows.firstMatch.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
