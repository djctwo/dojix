import AppKit
import Foundation
import XCTest
@testable import Dojix

/// App Lock triggers beyond SwiftUI's scenePhase, and prop-firm settings kept in the
/// encrypted journal instead of UserDefaults. All values are fictional.
final class AutoLockAndSettingsTests: XCTestCase {
    // MARK: - Auto-lock

    private final class Counter: @unchecked Sendable {
        var count = 0
    }

    @MainActor
    private func lockCount(afterPosting name: Notification.Name, on which: KeyPath<Centers, NotificationCenter>) -> Int {
        let centers = Centers()
        let counter = Counter()
        let monitor = AutoLockMonitor(workspaceCenter: centers.workspace, distributedCenter: centers.distributed,
                                      appCenter: centers.app) { counter.count += 1 }
        defer { monitor.stop() }
        centers[keyPath: which].post(name: name, object: nil)
        // Observers run on the main queue: let it drain.
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        return counter.count
    }

    private struct Centers {
        let workspace = NotificationCenter()
        let distributed = NotificationCenter()
        let app = NotificationCenter()
    }

    @MainActor
    func testLocksOnScreenLockSleepUserSwitchHideAndMinimize() {
        XCTAssertEqual(lockCount(afterPosting: NSWorkspace.willSleepNotification, on: \.workspace), 1)
        XCTAssertEqual(lockCount(afterPosting: NSWorkspace.screensDidSleepNotification, on: \.workspace), 1)
        XCTAssertEqual(lockCount(afterPosting: NSWorkspace.sessionDidResignActiveNotification, on: \.workspace), 1)
        XCTAssertEqual(lockCount(afterPosting: Notification.Name("com.apple.screenIsLocked"), on: \.distributed), 1)
        XCTAssertEqual(lockCount(afterPosting: NSApplication.didHideNotification, on: \.app), 1)
        XCTAssertEqual(lockCount(afterPosting: NSWindow.didMiniaturizeNotification, on: \.app), 1)
    }

    @MainActor
    func testUnrelatedNotificationsDoNotLock() {
        XCTAssertEqual(lockCount(afterPosting: NSWorkspace.didWakeNotification, on: \.workspace), 0)
        XCTAssertEqual(lockCount(afterPosting: Notification.Name("com.apple.screenIsUnlocked"), on: \.distributed), 0)
        XCTAssertEqual(lockCount(afterPosting: NSApplication.didBecomeActiveNotification, on: \.app), 0)
    }

    @MainActor
    func testStoppedMonitorNoLongerLocks() {
        let center = NotificationCenter()
        let counter = Counter()
        let monitor = AutoLockMonitor(workspaceCenter: center, distributedCenter: NotificationCenter(),
                                      appCenter: NotificationCenter()) { counter.count += 1 }
        monitor.stop()
        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(counter.count, 0)
    }

    // MARK: - Prop-firm settings live in the encrypted journal

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "com.dojix.tests.propfirm.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    func testSettingsAreStoredInTheJournalNotUserDefaults() throws {
        let database = try DatabaseManager(inMemory: true)
        let repository = SettingsRepository(database: database)
        let settings = PropFirmSettings(accountSize: 250_000, profitTarget: 10, maxDailyLoss: 4, maxTotalDrawdown: 8)
        try settings.save(to: repository)

        XCTAssertEqual(try PropFirmSettings.load(from: repository), settings)
        XCTAssertEqual(try repository.string(for: PropFirmSettings.Key.accountSize), "250000.0")
        XCTAssertNil(UserDefaults.standard.object(forKey: PropFirmSettings.Key.accountSize))
    }

    func testInvalidStoredValuesFallBackToDefaults() throws {
        // A restored backup can hold anything in the settings table.
        let repository = SettingsRepository(database: try DatabaseManager(inMemory: true))
        try repository.set([PropFirmSettings.Key.accountSize: "nan", PropFirmSettings.Key.profitTarget: "-3",
                            PropFirmSettings.Key.maxDailyLoss: "1e300", PropFirmSettings.Key.maxTotalDrawdown: "x"])
        XCTAssertEqual(try PropFirmSettings.load(from: repository), PropFirmSettings())

        try PropFirmSettings(accountSize: .infinity).save(to: repository)
        XCTAssertEqual(try repository.string(for: PropFirmSettings.Key.accountSize), "nan",
                       "an invalid value is never written")
    }

    func testLegacyDefaultsMoveIntoTheJournalAndAreDeleted() throws {
        try withDefaults { defaults in
            defaults.set(50_000.0, forKey: PropFirmSettings.Key.accountSize)
            defaults.set(6.0, forKey: PropFirmSettings.Key.profitTarget)
            let repository = SettingsRepository(database: try DatabaseManager(inMemory: true))
            try repository.set([PropFirmSettings.Key.profitTarget: "12.0"])

            try PropFirmSettings.migrateLegacyDefaults(defaults, into: repository)

            let loaded = try PropFirmSettings.load(from: repository)
            XCTAssertEqual(loaded.accountSize, 50_000)
            XCTAssertEqual(loaded.profitTarget, 12, "a value already in the journal wins")
            for key in PropFirmSettings.Key.all {
                XCTAssertNil(defaults.object(forKey: key), "\(key) left in the preferences file")
            }
        }
    }

    func testEraseAllRemovesLegacyDefaults() throws {
        try withDefaults { defaults in
            defaults.set(75_000.0, forKey: PropFirmSettings.Key.accountSize)
            let database = try DatabaseManager(inMemory: true)
            let shots = try SecFixture.scratchDirectory()
            try LocalDataEraser.eraseAll(database: database, screenshotsDirectory: shots, defaults: defaults)
            XCTAssertNil(defaults.object(forKey: PropFirmSettings.Key.accountSize))
        }
    }
}
