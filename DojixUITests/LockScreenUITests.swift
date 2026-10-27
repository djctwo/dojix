import XCTest

/// UI tests for App Lock: enable it, relaunch into the lock screen, wrong and right
/// password, disable it (needs the current password), the forgot-password erase, the
/// "Lock when idle" setting and the backup sheet's password option.
///
/// Each test uses its own data folder and its own Keychain service, so the lock it turns
/// on (a database key wrapped with the password) never affects any other test.
final class LockScreenUITests: XCTestCase {

    private var app: XCUIApplication!
    private let password = "fictional-pass-123"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = []
        // Keep test runs away from any real journal: private data folder, no MT5 folder,
        // and a Keychain service of its own (the wrapped key must not leak to other tests).
        let id = UUID().uuidString
        let scratch = UITestPaths.scratchRoot + "/dojix-uitests-\(id)"
        app.launchEnvironment["DOJIX_DATA_DIR"] = scratch + "/data"
        app.launchEnvironment["DOJIX_MT5_DIR"] = scratch + "/mt5"
        app.launchEnvironment["DOJIX_KEYCHAIN_SERVICE"] = "dojix-uitests-lock-\(id)"
        // Skip the first-run tour (sets the app's preference for this launch only)
        app.launchArguments += ["-first_onboarding_done", "YES"]
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    // MARK: - Helpers

    private func launchAndWait() {
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
    }

    private func type(_ text: String, into field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 5), "missing field \(field)")
        field.click()
        field.typeText(text)
    }

    /// Settings > Security > Enable App Lock, with `password`.
    private func enableAppLock() {
        app.typeKey(",", modifierFlags: .command)
        let enable = app.buttons["Enable App Lock"].firstMatch
        XCTAssertTrue(enable.waitForExistence(timeout: 5))
        enable.click()
        type(password, into: app.secureTextFields["New Password"])
        type(password, into: app.secureTextFields["Confirm Password"])
        app.buttons["Set Password"].click()
        // The key is wrapped (PBKDF2 600,000 rounds): allow a few seconds on CI
        XCTAssertTrue(app.buttons["Disable App Lock"].firstMatch.waitForExistence(timeout: 20),
                      "App Lock should be on")
    }

    private func relaunchToLockScreen() -> XCUIElement {
        app.terminate()
        launchAndWait()
        let lockTitle = app.staticTexts["Dojix is Locked"]
        XCTAssertTrue(lockTitle.waitForExistence(timeout: 15), "a relaunch with App Lock on shows the lock screen")
        XCTAssertTrue(app.buttons["Unlock"].exists)
        XCTAssertTrue(app.buttons["Forgot Password?"].exists)
        return lockTitle
    }

    // MARK: - Lock flow

    func testEnableRelaunchUnlockAndDisable() throws {
        launchAndWait()
        enableAppLock()

        let lockTitle = relaunchToLockScreen()

        // Wrong password: refused, the journal stays closed
        let field = app.secureTextFields["Password"]
        type("wrong-password\r", into: field)
        XCTAssertTrue(app.staticTexts["Incorrect password (1/5)"].waitForExistence(timeout: 20))
        XCTAssertTrue(lockTitle.exists)

        // Right password: unlocks
        type(password + "\r", into: field)
        XCTAssertTrue(lockTitle.waitForNonExistence(timeout: 20), "the right password unlocks Dojix")

        // Disabling needs the current password
        app.typeKey(",", modifierFlags: .command)
        let disable = app.buttons["Disable App Lock"].firstMatch
        XCTAssertTrue(disable.waitForExistence(timeout: 5))
        disable.click()
        type("not-the-password", into: app.secureTextFields["Current Password"])
        app.buttons["Disable"].click()
        XCTAssertTrue(app.staticTexts["Current password is incorrect"].waitForExistence(timeout: 20))
        let current = app.secureTextFields["Current Password"]
        current.click()
        current.typeKey("a", modifierFlags: .command)
        current.typeText(password)
        app.buttons["Disable"].click()
        XCTAssertTrue(app.buttons["Enable App Lock"].firstMatch.waitForExistence(timeout: 20), "App Lock is off")

        // Relaunch: no lock screen
        app.terminate()
        launchAndWait()
        XCTAssertFalse(app.staticTexts["Dojix is Locked"].waitForExistence(timeout: 3))
    }

    func testForgotPasswordErasesAndStartsFresh() throws {
        launchAndWait()
        enableAppLock()
        let lockTitle = relaunchToLockScreen()

        app.buttons["Forgot Password?"].click()
        XCTAssertTrue(
            app.staticTexts["Erase All Local Data?"].waitForExistence(timeout: 5),
            "Forgot password should offer erase-and-start-fresh, not silently remove the lock"
        )
        app.buttons["Erase Everything"].click()

        XCTAssertTrue(lockTitle.waitForNonExistence(timeout: 15), "after erasing, Dojix opens empty")
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Enable App Lock"].firstMatch.waitForExistence(timeout: 5),
                      "the lock is gone along with the data")
    }

    // MARK: - Idle lock setting

    func testIdleLockSettingDefaultsTo15MinutesAndCanBeTurnedOff() throws {
        launchAndWait()
        enableAppLock()
        let picker = app.popUpButtons["idleLockPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "Lock when idle appears once App Lock is on")
        XCTAssertEqual(picker.value as? String, "After 15 minutes", "default 15 minutes")
        picker.click()
        let off = app.menuItems["Off"]
        XCTAssertTrue(off.waitForExistence(timeout: 5))
        off.click()
        XCTAssertEqual(picker.value as? String, "Off")
    }

    // MARK: - Backup sheet

    /// Scroll the Settings form until `element` can be clicked.
    private func scrollTo(_ element: XCUIElement) {
        let form = app.scrollViews.firstMatch
        for _ in 0..<15 where !(element.exists && element.isHittable) {
            form.scroll(byDeltaX: 0, deltaY: -300)
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5), "missing \(element)")
    }

    private func openExportSheet() -> XCUIElement {
        app.typeKey(",", modifierFlags: .command)
        let export = app.buttons["Export Backup"].firstMatch
        scrollTo(export)
        export.click()
        let toggle = app.descendants(matching: .any)["protectBackupToggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "the export sheet offers password protection")
        return toggle
    }

    private func isOn(_ toggle: XCUIElement) -> Bool {
        if let number = toggle.value as? Int { return number == 1 }
        if let flag = toggle.value as? Bool { return flag }
        return (toggle.value as? String) == "1"
    }

    func testBackupPasswordIsOnByDefaultWithAppLock() throws {
        launchAndWait()
        enableAppLock()
        let toggle = openExportSheet()
        XCTAssertTrue(isOn(toggle), "with App Lock on, protecting the backup is the default")
        XCTAssertTrue(app.secureTextFields["Backup Password"].exists)
        XCTAssertTrue(app.secureTextFields["Confirm Backup Password"].exists)
        // A short password is refused before any file panel opens
        type("short", into: app.secureTextFields["Backup Password"])
        type("short", into: app.secureTextFields["Confirm Backup Password"])
        app.buttons["Choose Location…"].click()
        XCTAssertTrue(app.staticTexts["Password must be at least 8 characters"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].click()
        XCTAssertTrue(toggle.waitForNonExistence(timeout: 5))
    }

    func testBackupPasswordIsOffByDefaultWithoutAppLock() throws {
        launchAndWait()
        let toggle = openExportSheet()
        XCTAssertFalse(isOn(toggle), "without App Lock, the default is an unencrypted backup")
        XCTAssertFalse(app.secureTextFields["Backup Password"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", "anyone who gets the file", "anyone who gets the file"))
            .firstMatch.exists, "the sheet warns that an unprotected backup is readable")
        toggle.click()
        XCTAssertTrue(app.secureTextFields["Backup Password"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].click()
    }

    // MARK: - Normal Launch (No Lock)

    func testNormalLaunchSkipsLockScreen() throws {
        launchAndWait()
        let lockTitle = app.staticTexts["Dojix is Locked"]
        XCTAssertFalse(lockTitle.waitForExistence(timeout: 3), "a fresh install is not locked")
    }
}
