import Foundation

/// Bookkeeping that keeps locks and "Erase Everything" ordered with key operations that
/// run partly off the main actor (password checks, re-sealing files, Keychain writes).
extension AppState {
    // MARK: - Locks requested while an unlock or Enable App Lock runs

    /// A lock requested from now until `endDeferringLocks` is remembered, not dropped.
    @MainActor
    func beginDeferringLocks() {
        lockDeferrals += 1
    }

    /// Carry out a lock requested meanwhile (once nothing defers locks any more).
    @MainActor
    func endDeferringLocks() {
        lockDeferrals -= 1
        guard lockDeferrals == 0, isLockRequestedMeanwhile else { return }
        isLockRequestedMeanwhile = false
        lock()
    }

    // MARK: - Key operations vs "Erase Everything"

    @MainActor
    func beginKeyOperation() {
        keyOperationsInFlight += 1
    }

    @MainActor
    func endKeyOperation() {
        keyOperationsInFlight -= 1
        guard keyOperationsInFlight == 0 else { return }
        let waiters = keyOperationWaiters
        keyOperationWaiters = []
        waiters.forEach { $0.resume() }
    }

    /// Returns once no key operation is running. The caller must not suspend between
    /// this and its own work, so none can start in between.
    @MainActor
    func waitForKeyOperations() async {
        while keyOperationsInFlight > 0 {
            await withCheckedContinuation { keyOperationWaiters.append($0) }
        }
    }
}
