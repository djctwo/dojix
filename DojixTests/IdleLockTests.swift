import AppKit
import XCTest
@testable import Dojix

/// Idle auto-lock: locks after N minutes with no keyboard/mouse activity, not before;
/// activity resets the time; Off never locks. The clock is injected.
@MainActor
final class IdleLockTests: XCTestCase {
    private final class Clock {
        var now = Date(timeIntervalSince1970: 1_767_225_600)
        func advance(minutes: Int) { now = now.addingTimeInterval(TimeInterval(minutes * 60)) }
        func advance(seconds: Int) { now = now.addingTimeInterval(TimeInterval(seconds)) }
    }

    private var clock = Clock()
    private var minutes = 15
    private var tracking = true
    private var locks = 0

    override func setUp() {
        clock = Clock()
        minutes = 15
        tracking = true
        locks = 0
    }

    private func makeTimer() -> IdleLockTimer {
        IdleLockTimer(now: { [unowned self] in clock.now }, minutes: { [unowned self] in minutes },
                      isTracking: { [unowned self] in tracking }, lock: { [unowned self] in locks += 1 })
    }

    func testLocksAtTheThresholdAndNotBefore() {
        let idle = makeTimer()
        clock.advance(seconds: 15 * 60 - 1)
        idle.tick()
        XCTAssertEqual(locks, 0, "not before 15 minutes")
        clock.advance(seconds: 1)
        idle.tick()
        XCTAssertEqual(locks, 1, "at 15 minutes")
        idle.tick()
        XCTAssertEqual(locks, 1, "once, then the idle time starts over")
    }

    func testActivityResetsTheIdleTime() {
        let idle = makeTimer()
        clock.advance(minutes: 10)
        idle.noteActivity()
        clock.advance(minutes: 10)
        idle.tick()
        XCTAssertEqual(locks, 0, "only 10 minutes since the last activity")
        clock.advance(minutes: 5)
        idle.tick()
        XCTAssertEqual(locks, 1)
    }

    func testOffNeverLocks() {
        minutes = 0
        let idle = makeTimer()
        clock.advance(minutes: 600)
        idle.tick()
        XCTAssertEqual(locks, 0)
        // Turning it on later starts counting from then, not from hours ago
        minutes = 1
        idle.tick()
        XCTAssertEqual(locks, 0)
        clock.advance(minutes: 1)
        idle.tick()
        XCTAssertEqual(locks, 1)
    }

    func testEveryChoiceLocksAtItsOwnThreshold() {
        for choice in IdleLockSetting.choices where choice > 0 {
            setUp()
            minutes = choice
            let idle = makeTimer()
            clock.advance(seconds: choice * 60 - 1)
            idle.tick()
            XCTAssertEqual(locks, 0, "\(choice) min: too early")
            clock.advance(seconds: 1)
            idle.tick()
            XCTAssertEqual(locks, 1, "\(choice) min")
        }
    }

    func testNoLockWhileNotTrackingAndTimeStartsOverAfterwards() {
        // Already locked, App Lock off, or a save/open panel is up
        tracking = false
        let idle = makeTimer()
        clock.advance(minutes: 60)
        idle.tick()
        XCTAssertEqual(locks, 0)
        tracking = true // unlocked again
        idle.tick()
        XCTAssertEqual(locks, 0, "time spent locked doesn't count")
        clock.advance(minutes: 15)
        idle.tick()
        XCTAssertEqual(locks, 1)
    }

    // MARK: - Setting

    func testSettingDefaultsTo15MinutesAndOnlyAcceptsTheChoices() throws {
        let suite = "com.dojix.tests.idle.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(IdleLockSetting.choices, [0, 1, 5, 15, 30, 60])
        XCTAssertEqual(IdleLockSetting.minutes(in: defaults), 15, "default for new and existing users")
        IdleLockSetting.set(0, in: defaults)
        XCTAssertEqual(IdleLockSetting.minutes(in: defaults), 0, "Off is kept")
        IdleLockSetting.set(7, in: defaults)
        XCTAssertEqual(IdleLockSetting.minutes(in: defaults), 0, "not a choice: ignored")
        defaults.set(42, forKey: IdleLockSetting.defaultsKey)
        XCTAssertEqual(IdleLockSetting.minutes(in: defaults), 15, "damaged value: default")
        XCTAssertEqual(IdleLockSetting.title(for: 0), "Off")
        XCTAssertEqual(IdleLockSetting.title(for: 1), "After 1 minute")
        XCTAssertEqual(IdleLockSetting.title(for: 15), "After 15 minutes")
    }

    // MARK: - Wiring

    func testMonitorInstallsAndRemovesIdleTracking() {
        let monitor = AutoLockMonitor(workspaceCenter: NotificationCenter(), distributedCenter: NotificationCenter(),
                                      appCenter: NotificationCenter()) {}
        let idle = makeTimer()
        monitor.startIdleTracking(idle, checkEvery: 0.01)
        XCTAssertTrue(monitor.idleLock === idle)
        minutes = 1
        clock.advance(minutes: 2)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(locks, 1, "the timer ticks the idle lock")
        monitor.stop()
        XCTAssertNil(monitor.idleLock)
        clock.advance(minutes: 2)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(locks, 1, "stopped: no more ticks")
    }

    /// The idle check must also run while a modal panel, sheet/alert or menu runs the
    /// run loop in its own mode (a default-mode timer would never fire: fail open).
    func testIdleCheckRunsWhileAModalPanelOrMenuIsOpen() {
        for mode in [RunLoop.Mode.modalPanel, .eventTracking] {
            setUp()
            minutes = 1
            let monitor = AutoLockMonitor(workspaceCenter: NotificationCenter(), distributedCenter: NotificationCenter(),
                                          appCenter: NotificationCenter()) {}
            monitor.startIdleTracking(makeTimer(), checkEvery: 0.01)
            clock.advance(minutes: 2)
            let deadline = Date().addingTimeInterval(1)
            while locks == 0, Date() < deadline {
                RunLoop.main.run(mode: mode, before: Date().addingTimeInterval(0.05))
            }
            monitor.stop()
            XCTAssertEqual(locks, 1, "idle lock must fire in \(mode.rawValue)")
        }
    }

    // MARK: - Locking covers everything

    private final class FakeHost: ModalUIHost {
        var hasModalSession = false
        var aborted = 0
        var endedSheets = 0
        func abortModalSession() { aborted += 1; hasModalSession = false }
        func endAllSheets() { endedSheets += 1 }
    }

    func testLockingClosesModalPanelsAndSheets() {
        let host = FakeHost()
        host.hasModalSession = true
        LockCover.dismissModalUI(in: host)
        XCTAssertEqual(host.aborted, 1, "an open/save panel or alert is cancelled")
        XCTAssertEqual(host.endedSheets, 1, "sheets and alerts are closed")

        let idleHost = FakeHost()
        LockCover.dismissModalUI(in: idleHost)
        XCTAssertEqual(idleHost.aborted, 0, "no modal session: nothing to abort")
        XCTAssertEqual(idleHost.endedSheets, 1)
    }
}
