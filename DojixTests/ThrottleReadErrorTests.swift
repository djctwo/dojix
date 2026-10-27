import Foundation
import Security
import XCTest
@testable import Dojix

/// The wrong-password back-off fails closed: a count or wait that exists but can't be read
/// from the Keychain (locked keychain, a refused access prompt) means "locked out", never
/// "no wait", and the stored count is never rewritten as 1. All values are fictional.
@MainActor
final class ThrottleReadErrorTests: XCTestCase {
    /// Keychain stand-in whose reads of chosen accounts fail (the items still exist)
    private final class PartlyUnreadableStore: SecretStore, @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String: String] = [:]
        private var unreadable: Set<String> = []

        func failReads(of accounts: Set<String>) { lock.withLock { unreadable = accounts } }

        func read(_ account: String) -> (value: String?, status: OSStatus) {
            lock.withLock {
                if unreadable.contains(account) { return (nil, errSecInteractionNotAllowed) }
                guard let value = items[account] else { return (nil, errSecItemNotFound) }
                return (value, errSecSuccess)
            }
        }

        @discardableResult
        func write(_ account: String, _ value: String) -> Bool {
            lock.withLock { items[account] = value }
            return true
        }

        func delete(_ account: String) { lock.withLock { items[account] = nil } }

        func value(_ account: String) -> String? { lock.withLock { items[account] } }
    }

    private let store = PartlyUnreadableStore()
    private let clock = Shared(Date(timeIntervalSince1970: 1_800_000_000))
    private var throttle: UnlockThrottle {
        let clock = self.clock
        return UnlockThrottle(store: store, now: { clock.value })
    }

    private var stored: (String?, String?) {
        (store.value(UnlockThrottle.attemptsKey), store.value(UnlockThrottle.lockoutUntilKey))
    }

    /// Before the wait starts (3 wrong passwords): an unreadable count used to read as 0 and
    /// the next wrong password wrote "1" over it
    func testUnreadableCountLocksOutAndIsNeverRewritten() {
        for _ in 1...3 { throttle.recordFailure() }
        XCTAssertFalse(throttle.isLockedOut, "Setup: no wait yet")
        let before = stored

        store.failReads(of: [UnlockThrottle.attemptsKey])
        XCTAssertTrue(throttle.isLockedOut, "An unreadable count means locked out")
        XCTAssertTrue(throttle.lockoutMessage()?.contains("Keychain") == true, throttle.lockoutMessage() ?? "nil")
        let message = throttle.recordFailure()
        XCTAssertTrue(message.contains("Keychain"), message)
        store.failReads(of: [])
        XCTAssertEqual(stored.0, before.0, "Count untouched")
        XCTAssertEqual(stored.1, before.1)
        XCTAssertEqual(throttle.failedAttempts, 3)
        XCTAssertFalse(throttle.isLockedOut, "Readable again: back to normal")
    }

    /// During a wait (5 wrong passwords): an unreadable wait used to read as "no wait"
    func testUnreadableWaitStillLocksOutAndIsNeverRewritten() {
        for _ in 1...5 { throttle.recordFailure() }
        XCTAssertTrue(throttle.isLockedOut, "Setup: waiting")
        let before = stored

        store.failReads(of: [UnlockThrottle.lockoutUntilKey])
        XCTAssertTrue(throttle.isLockedOut, "An unreadable wait is still a wait")
        throttle.recordFailure()
        store.failReads(of: [])
        XCTAssertEqual(stored.0, before.0, "Count untouched")
        XCTAssertEqual(stored.1, before.1, "Wait untouched")

        clock.value = clock.value.addingTimeInterval(31)
        XCTAssertFalse(throttle.isLockedOut)
        throttle.recordFailure()
        XCTAssertEqual(throttle.failedAttempts, 6, "Counting carries on from the real count")
    }

    /// Settings' Turn Off: no password is checked while the count can't be read
    func testSettingsChecksNoPasswordWhileTheCountCantBeRead() async throws {
        let throttle = self.throttle
        for _ in 1...2 { throttle.recordFailure() }
        let vm = SettingsViewModel(repository: TradeRepository(database: try DatabaseManager(inMemory: true)),
                                   throttle: throttle)
        let lock = FakeAppLock()
        lock.isAppLockOn = true
        vm.isAppLockEnabled = true
        lock.result = { throw DatabaseKeyVault.VaultError.wrongPassword }

        store.failReads(of: [UnlockThrottle.attemptsKey])
        vm.currentPassword = "fictional-guess"
        await vm.disableAppLock(appState: lock)
        XCTAssertEqual(lock.calls, 0, "No password checked")
        XCTAssertTrue(vm.passwordError?.contains("Keychain") == true, vm.passwordError ?? "nil")
        store.failReads(of: [])
        XCTAssertEqual(throttle.failedAttempts, 2, "Count untouched")
    }
}
