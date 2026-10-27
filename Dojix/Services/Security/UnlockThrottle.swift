import Foundation
import Security
import os

/// Back-off after wrong App Lock passwords, shared by every place that checks the
/// password: the lock screen, the "older journal" screen, and Settings (Change Password,
/// Disable App Lock). Kept in the Keychain so it survives a relaunch. A UI throttle only:
/// offline guessing still costs 600,000 PBKDF2 rounds per try. Fails closed: while the
/// count or the wait exists but can't be read (only errSecItemNotFound means "none"), it
/// counts as locked out and nothing is written, so the count is never restarted at 1.
struct UnlockThrottle: Sendable {
    static let attemptsKey = "lock_failed_attempts"
    static let lockoutUntilKey = "lock_lockout_until"
    /// Shown instead of a wait while the Keychain won't return the count or the wait
    static let unreadableMessage = "Dojix can't read its wrong-password count from the Keychain right now, "
        + "so no password can be checked. If macOS asked about Keychain access, allow it; otherwise quit and "
        + "reopen Dojix."

    private static let logger = Logger(subsystem: "com.dojix", category: "UnlockThrottle")

    /// The app's throttle (Keychain-backed).
    static let shared = UnlockThrottle()

    let store: any SecretStore
    let now: @Sendable () -> Date

    /// - Parameters:
    ///   - store: where the count and lockout end are kept (tests inject a memory store).
    ///   - now: the clock (tests inject one).
    init(store: any SecretStore = KeychainSecretStore(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.now = now
    }

    /// Persistent count of wrong passwords since the last right one (0 if it can't be read;
    /// `isUnreadable` then locks out).
    var failedAttempts: Int {
        guard let text = readable(Self.attemptsKey), let count = Int(text) else { return 0 }
        return count
    }

    /// Seconds left before another try is allowed (nil = no wait running, or the wait can't
    /// be read: see `isUnreadable`).
    func secondsRemaining() -> Int? {
        let current = now().timeIntervalSince1970
        guard let text = readable(Self.lockoutUntilKey), let until = TimeInterval(text),
              current < until else { return nil }
        return Int(saturating: until - current)
    }

    /// The count or the wait exists but the Keychain wouldn't return it (fail closed).
    var isUnreadable: Bool {
        [Self.attemptsKey, Self.lockoutUntilKey].contains { account in
            let status = store.read(account).status
            guard status != errSecSuccess, status != errSecItemNotFound else { return false }
            Self.logger.error("Wrong-password limit unreadable (status \(status)); no password checked")
            return true
        }
    }

    var isLockedOut: Bool { lockoutMessage() != nil }

    /// "Too many attempts. Try again in …" (or `unreadableMessage`), or nil when a
    /// password may be checked.
    func lockoutMessage() -> String? {
        if isUnreadable { return Self.unreadableMessage }
        guard let remaining = secondsRemaining() else { return nil }
        return Self.waitMessage(seconds: remaining)
    }

    /// Lockout duration for the n-th wrong password (exponential back-off).
    static func lockoutDuration(for attempts: Int) -> TimeInterval {
        switch attempts {
        case 0...4: 0           // no lockout for the first 5 attempts
        case 5: 30              // 30 seconds
        case 6: 60              // 1 minute
        case 7: 300             // 5 minutes
        case 8: 900             // 15 minutes
        default: 1800           // 30 minutes
        }
    }

    /// Count a wrong password; returns the message to show. Writes nothing while the count
    /// or the wait can't be read (it is never restarted at 1).
    @discardableResult
    func recordFailure() -> String {
        guard !isUnreadable else { return Self.unreadableMessage }
        let newCount = min(failedAttempts, 1_000) + 1
        store.write(Self.attemptsKey, String(newCount))
        let lockout = Self.lockoutDuration(for: newCount)
        guard lockout > 0 else { return "Incorrect password (\(newCount)/5)" }
        store.write(Self.lockoutUntilKey, String(now().timeIntervalSince1970 + lockout))
        return Self.waitMessage(seconds: Int(saturating: lockout))
    }

    /// The right password was entered.
    func reset() {
        store.delete(Self.attemptsKey)
        store.delete(Self.lockoutUntilKey)
    }

    /// The item's value; nil when absent or unreadable
    private func readable(_ account: String) -> String? {
        let (value, status) = store.read(account)
        return status == errSecSuccess ? value : nil
    }

    private static func waitMessage(seconds: Int) -> String {
        seconds > 60 ? "Too many attempts. Try again in \(seconds / 60) minutes."
            : "Too many attempts. Try again in \(seconds) seconds."
    }
}
