import AppKit

/// Locks Dojix (when App Lock is on) at the moments a Mac is typically left alone: the
/// screen locks, the display or the Mac goes to sleep, another user takes over the screen
/// (fast user switching), or Dojix is hidden or a window minimized; and, with
/// `startIdleTracking`, after the "Lock when idle" time without keyboard or mouse
/// activity in Dojix (`IdleLockTimer`).
///
/// SwiftUI's `scenePhase` alone misses these on macOS: a window that stays on screen
/// stays "active" while the screen is locked or the Mac sleeps. `AppState.lock()` is a
/// no-op when App Lock is off, so observing is harmless then.
@MainActor
final class AutoLockMonitor {
    /// `NSWorkspace` notifications that lock.
    static let workspaceTriggers: [Notification.Name] = [
        NSWorkspace.willSleepNotification,
        NSWorkspace.screensDidSleepNotification,
        NSWorkspace.sessionDidResignActiveNotification,
    ]
    /// Posted by macOS (distributed notification) when the screen is locked.
    static let screenLockedNotification = Notification.Name("com.apple.screenIsLocked")
    /// In-app notifications that lock.
    static let appTriggers: [Notification.Name] = [
        NSApplication.didHideNotification,
        NSWindow.didMiniaturizeNotification,
    ]

    /// Events that count as activity for the idle lock.
    static let activityEvents: NSEvent.EventTypeMask = [
        .keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown,
        .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel,
        .magnify, .rotate, .swipe,
    ]

    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var eventMonitor: Any?
    private var idleTimer: Timer?
    private(set) var idleLock: IdleLockTimer?

    /// - Parameters: the notification centers to observe (tests pass private ones) and
    ///   the lock action.
    init(workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
         distributedCenter: NotificationCenter = DistributedNotificationCenter.default(),
         appCenter: NotificationCenter = .default,
         lock: @escaping @MainActor @Sendable () -> Void) {
        for name in Self.workspaceTriggers {
            observe(name, on: workspaceCenter, lock: lock)
        }
        observe(Self.screenLockedNotification, on: distributedCenter, lock: lock)
        for name in Self.appTriggers {
            observe(name, on: appCenter, lock: lock)
        }
    }

    /// Lock after the idle time: every keyboard or mouse event in Dojix (a local event
    /// monitor, which only sees Dojix's own events) resets the idle time, and a timer
    /// checks it every `interval` seconds (also while a menu or panel runs its own loop).
    func startIdleTracking(_ idle: IdleLockTimer, checkEvery interval: TimeInterval = 5) {
        stopIdleTracking()
        idleLock = idle
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: Self.activityEvents) { [weak idle] event in
            // Local monitors run on the main thread.
            MainActor.assumeIsolated { idle?.noteActivity() }
            return event
        }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak idle] _ in
            // Scheduled on the main run loop below.
            MainActor.assumeIsolated { idle?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    private func stopIdleTracking() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        idleTimer?.invalidate()
        idleTimer = nil
        idleLock = nil
    }

    /// Stop observing.
    func stop() {
        for (center, token) in observers {
            center.removeObserver(token)
        }
        observers = []
        stopIdleTracking()
    }

    private func observe(_ name: Notification.Name, on center: NotificationCenter,
                         lock: @escaping @MainActor @Sendable () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            // queue: .main, so this runs on the main thread.
            MainActor.assumeIsolated { lock() }
        }
        observers.append((center, token))
    }
}
