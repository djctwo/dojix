import Foundation

/// The "Lock when idle" setting (App Lock on): Off, or 1, 5, 15, 30 or 60 minutes without
/// keyboard or mouse activity in Dojix. Default 15 minutes, for new and existing users.
/// A UI preference, not secret, so it lives in UserDefaults.
enum IdleLockSetting {
    static let defaultsKey = "app_lock_idle_minutes"
    /// 0 = Off.
    static let choices = [0, 1, 5, 15, 30, 60]
    static let defaultMinutes = 15

    /// The stored choice; missing or invalid values give the default.
    static func minutes(in defaults: UserDefaults = .standard) -> Int {
        guard defaults.object(forKey: defaultsKey) != nil else { return defaultMinutes }
        let stored = defaults.integer(forKey: defaultsKey)
        return choices.contains(stored) ? stored : defaultMinutes
    }

    static func set(_ minutes: Int, in defaults: UserDefaults = .standard) {
        guard choices.contains(minutes) else { return }
        defaults.set(minutes, forKey: defaultsKey)
    }

    /// "Off", "After 1 minute", "After 5 minutes", …
    static func title(for minutes: Int) -> String {
        switch minutes {
        case 0: "Off"
        case 1: "After 1 minute"
        default: "After \(minutes) minutes"
        }
    }
}

/// Decides when Dojix has been idle long enough to lock. Activity (keyboard or mouse
/// events in the app) is reported with `noteActivity()`; `tick()` is called
/// periodically and locks once the configured number of minutes has passed with no
/// activity. The clock, the setting and "should we track at all" are injected, so this
/// is unit-tested without timers or events (see `AutoLockMonitor` for the wiring).
@MainActor
final class IdleLockTimer {
    private let now: () -> Date
    private let minutes: () -> Int
    private let isTracking: () -> Bool
    private let lock: () -> Void
    private(set) var lastActivity: Date

    /// - Parameters:
    ///   - now: the clock.
    ///   - minutes: the current setting (0 = Off).
    ///   - isTracking: false while there is nothing to protect (already locked, or the
    ///     journal not open); the idle time then starts over.
    ///   - lock: the app's lock action (saves, closes, wipes the key from memory).
    init(now: @escaping () -> Date = { Date() }, minutes: @escaping () -> Int = { IdleLockSetting.minutes() },
         isTracking: @escaping () -> Bool, lock: @escaping () -> Void) {
        self.now = now
        self.minutes = minutes
        self.isTracking = isTracking
        self.lock = lock
        self.lastActivity = now()
    }

    /// A keyboard or mouse event happened in the app.
    func noteActivity() {
        lastActivity = now()
    }

    /// Lock if the app has been idle for the configured time.
    func tick() {
        let current = now()
        let limit = minutes()
        guard limit > 0, isTracking() else {
            // Off, or nothing to track: idle time starts over when tracking resumes.
            lastActivity = current
            return
        }
        guard current.timeIntervalSince(lastActivity) >= TimeInterval(limit * 60) else { return }
        lastActivity = current
        lock()
    }
}
