import CryptoKit
import Security
import XCTest
@testable import Dojix

/// Fixes from the finish-line review: key operations started from two windows at once
/// (L1) and a lock screen left up when App Lock was never actually set (L2). Scratch
/// folders and in-memory key stores only.
@MainActor
final class FinishLineFixTests: XCTestCase {
    private let fast: UInt32 = 1_000
    private let password = "fictional-lock-pw"
    private let newPassword = "new-fictional-pw"
    private let otherPassword = "other-fictional-pw"
    private var dir: URL!
    private var store: MemorySecretStore!
    private var vault: DatabaseKeyVault!

    override func setUp() async throws {
        dir = try SecFixture.scratchDirectory()
        store = MemorySecretStore()
        vault = DatabaseKeyVault(store: store, iterations: fast)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private var dbPath: String { dir.appendingPathComponent("Dojix.sqlite").path }
    private var shotsDir: URL { dir.appendingPathComponent("Screenshots") }

    /// Two trades sealed with a bare key (App Lock off), or with `lockOn` App Lock set
    /// with `password`; saved and closed.
    private func makeJournal(lockOn: Bool) throws {
        let key = try vault.createPlainKey()
        let db = try DatabaseManager(path: dbPath)
        try db.load(key: key)
        _ = try TradeRepository(database: db).bulkInsert([SecFixture.trade(ticket: 1), SecFixture.trade(ticket: 2)])
        if lockOn {
            let shots = ScreenshotManager(baseDir: shotsDir, keyProvider: { [db] in db.currentKey })
            try KeyRotation.rotate(vault: vault, database: db, screenshots: shots, oldKey: key, password: password)
        }
        try db.unload()
    }

    private func makeApp() throws -> AppState {
        AppState(database: try DatabaseManager(path: dbPath), vault: vault, screenshotsDirectory: shotsDir,
                 instanceLockDirectory: nil)
    }

    /// A hook that stops only the first operation that reaches it, until `release` fires.
    private func stopFirst(_ reached: Signal, _ release: Signal) -> @Sendable () async -> Void {
        let first = Shared(true)
        return {
            guard first.exchange(false) else { return }
            reached.fire()
            release.wait("release the first operation")
        }
    }

    /// Wait for `signal` without blocking the main actor (the code under test needs it).
    private func waitOffMain(_ signal: Signal, _ what: String) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                signal.wait(what)
                done.resume()
            }
        }
    }

    /// The stored key (wrapped with `password`) opens the journal on disk, with no
    /// rotation left pending.
    private func assertStoredKeyOpensJournal(password: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let keys = try vault.unwrapKeys(password: password)
        XCTAssertNil(keys.previous, "a rotation was left pending", file: file, line: line)
        XCTAssertTrue(KeyRotation.journalOpens(at: dbPath, with: keys.current),
                      "the journal is sealed with a key that isn't stored", file: file, line: line)
    }

    // MARK: - L1: one key operation at a time

    func testASecondPasswordChangeWhileOneIsRunningIsRefused() async throws {
        try makeJournal(lockOn: true)
        let app = try makeApp()
        _ = await app.unlock(password: password)
        let reached = Signal(), release = Signal()
        app.hooks.whileChangingKey = stopFirst(reached, release)

        let first = Task { @MainActor in try await app.changeAppLockPassword(current: password, new: newPassword) }
        await waitOffMain(reached, "first password change in progress")
        do {
            _ = try await app.changeAppLockPassword(current: password, new: otherPassword)
            XCTFail("a second password change ran alongside the first")
        } catch AppState.AppLockChangeError.busy {
            // Refused with a clear message, nothing changed.
        }
        release.fire()
        _ = try await first.value

        try assertStoredKeyOpensJournal(password: newPassword)
        XCTAssertThrowsError(try vault.unwrapKeys(password: otherPassword))
    }

    func testASecondEnableWhileOneIsRunningIsRefused() async throws {
        try makeJournal(lockOn: false)
        let app = try makeApp()
        XCTAssertFalse(app.isAppLockOn)
        let reached = Signal(), release = Signal()
        app.hooks.whileChangingKey = stopFirst(reached, release)

        let first = Task { @MainActor in try await app.enableAppLock(password: password) }
        await waitOffMain(reached, "first Enable in progress")
        do {
            _ = try await app.enableAppLock(password: otherPassword)
            XCTFail("a second Enable ran alongside the first")
        } catch AppState.AppLockChangeError.busy {
            XCTAssertEqual(AppState.AppLockChangeError.busy.errorDescription?.isEmpty, false)
        }
        release.fire()
        _ = try await first.value

        XCTAssertTrue(app.isAppLockOn)
        try assertStoredKeyOpensJournal(password: password)
    }

    func testASecondUnlockWhileOneIsRunningIsRefused() async throws {
        try makeJournal(lockOn: true)
        let app = try makeApp()
        XCTAssertTrue(app.isLocked)
        let reached = Signal(), release = Signal()
        app.hooks.whileUnlocking = stopFirst(reached, release)

        let first = Task { @MainActor in await app.unlock(password: password) }
        await waitOffMain(reached, "first unlock in progress")
        let second = await app.unlock(password: password)
        guard case .failed = second else { return XCTFail("a second unlock ran alongside the first: \(second)") }
        release.fire()
        let result = await first.value
        app.hooks.whileUnlocking = nil

        XCTAssertEqual(result, .unlocked)
        XCTAssertFalse(app.isLocked)
        XCTAssertEqual(try app.tradeRepository.count(), 2)
        try assertStoredKeyOpensJournal(password: password)
    }

    // MARK: - L2: no lock set → the lock screen opens like a relaunch would

    func testAFailedEnableOnAnUnreadableKeychainNeverLeavesALockScreenThatRejectsEveryPassword() async throws {
        try makeJournal(lockOn: false)
        let app = try makeApp()
        XCTAssertTrue(app.database.isLoaded)

        store.forcedReadStatus = errSecAuthFailed   // the user clicked Deny on a Keychain prompt
        do {
            _ = try await app.enableAppLock(password: password)
            XCTFail("Enable worked although the Keychain couldn't be read")
        } catch {
            // Expected: nothing was stored, and App Lock counts as on (fail closed).
        }
        XCTAssertTrue(app.isAppLockOn)
        store.forcedReadStatus = nil   // the Keychain answers again
        app.lock()
        XCTAssertTrue(app.isLocked)

        let result = await app.unlock(password: "any-fictional-attempt")
        XCTAssertEqual(result, .unlocked, "no lock was ever set, yet every password is rejected")
        XCTAssertFalse(app.isAppLockOn)
        XCTAssertFalse(app.isLocked)
        XCTAssertEqual(try vault.state(), .plain)
        XCTAssertEqual(try app.tradeRepository.count(), 2)
    }
}
