import Foundation
import XCTest
@testable import Dojix

/// Settings > Security: what the sheet reports after Enable / Change Password, and the
/// back-off for wrong current passwords (shared with the lock screen). All values are fictional.
@MainActor
final class SettingsLockTests: XCTestCase {
    private var throttleStore: MemorySecretStore!
    private var throttle: UnlockThrottle!
    private var clock: Shared<Date>!

    override func setUp() async throws {
        throttleStore = MemorySecretStore()
        let clock = Shared(Date(timeIntervalSince1970: 1_800_000_000))
        self.clock = clock
        throttle = UnlockThrottle(store: throttleStore, now: { clock.value })
    }

    private func makeViewModel() throws -> SettingsViewModel {
        let vm = SettingsViewModel(repository: TradeRepository(database: try DatabaseManager(inMemory: true)),
                                   throttle: throttle)
        vm.statusMessage = nil
        return vm
    }

    // MARK: - Finding 3

    func testAFailureAfterTheNewPasswordWasStoredShowsTheTruth() async throws {
        let vm = try makeViewModel()
        let lock = FakeAppLock()
        vm.isAppLockEnabled = false
        lock.lockOnAfterCall = true
        lock.result = { throw DatabaseEncryption.EncryptionError.encryptionFailed }
        vm.newPassword = "fictional-pass-1"
        vm.confirmPassword = "fictional-pass-1"

        await vm.setAppLockPassword(appState: lock)

        XCTAssertTrue(vm.isAppLockEnabled, "Settings must show the lock state actually in force")
    }

    func testAChangeThatFinishesOnTheNextUnlockSaysSo() async throws {
        let vm = try makeViewModel()
        let lock = FakeAppLock()
        lock.isAppLockOn = true
        vm.isAppLockEnabled = true
        lock.result = { .finishesOnNextUnlock }
        vm.currentPassword = "fictional-pass-1"
        vm.newPassword = "fictional-pass-2"
        vm.confirmPassword = "fictional-pass-2"

        await vm.setAppLockPassword(appState: lock)

        XCTAssertNil(vm.passwordError)
        XCTAssertFalse(vm.showSetPasswordSheet)
        XCTAssertTrue(vm.statusMessage?.contains("next time you unlock") == true, vm.statusMessage ?? "nil")
    }

    // MARK: - Finding 7: wrong current passwords are throttled

    private func wrongCurrentPasswordAttempts(_ count: Int, disable: Bool) async throws -> (SettingsViewModel, FakeAppLock) {
        let vm = try makeViewModel()
        let lock = FakeAppLock()
        lock.isAppLockOn = true
        vm.isAppLockEnabled = true
        lock.result = { throw DatabaseKeyVault.VaultError.wrongPassword }
        for _ in 0..<count {
            vm.currentPassword = "fictional-guess"
            vm.newPassword = "fictional-pass-2"
            vm.confirmPassword = "fictional-pass-2"
            if disable {
                await vm.disableAppLock(appState: lock)
            } else {
                await vm.setAppLockPassword(appState: lock)
            }
        }
        return (vm, lock)
    }

    func testChangePasswordChecksAreThrottled() async throws {
        let (vm, lock) = try await wrongCurrentPasswordAttempts(6, disable: false)
        XCTAssertEqual(lock.calls, 5, "the 6th guess must wait for the back-off")
        XCTAssertTrue(vm.passwordError?.contains("Too many attempts") == true, vm.passwordError ?? "nil")
        XCTAssertEqual(throttle.failedAttempts, 5)
    }

    func testDisableChecksAreThrottledAndShareTheLockScreenCount() async throws {
        throttle.recordFailure()   // one wrong try on the lock screen
        let (vm, lock) = try await wrongCurrentPasswordAttempts(5, disable: true)
        XCTAssertEqual(lock.calls, 4)
        XCTAssertTrue(vm.passwordError?.contains("Too many attempts") == true, vm.passwordError ?? "nil")
    }

    func testTheBackOffEndsAndARightPasswordResetsIt() async throws {
        let (vm, lock) = try await wrongCurrentPasswordAttempts(5, disable: true)
        clock.value = clock.value.addingTimeInterval(31)
        lock.result = { .complete }
        lock.lockOnAfterCall = false
        vm.currentPassword = "fictional-pass-1"
        await vm.disableAppLock(appState: lock)
        XCTAssertEqual(lock.calls, 6)
        XCTAssertEqual(throttle.failedAttempts, 0)
        XCTAssertFalse(vm.isAppLockEnabled)
    }
}
