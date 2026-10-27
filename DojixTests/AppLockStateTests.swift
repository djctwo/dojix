import CryptoKit
import Security
import XCTest
@testable import Dojix

/// App Lock as `AppState` runs it: locks that land in the middle of Enable / Change
/// Password / Disable, a Keychain that can't be read when locking, opening a journal on
/// a full disk or with an unreadable file, and a second running copy. Every AppState here
/// uses a scratch journal, an in-memory key store and a scratch screenshot folder.
@MainActor
final class AppLockStateTests: XCTestCase {
    private let fast: UInt32 = 1_000
    private let password = "fictional-lock-pw"
    private let newPassword = "new-fictional-pw"
    private var dir: URL!
    private var store: MemorySecretStore!
    private var vault: DatabaseKeyVault!
    private var immutable: [URL] = []

    override func setUp() async throws {
        dir = try SecFixture.scratchDirectory()
        store = MemorySecretStore()
        vault = DatabaseKeyVault(store: store, iterations: fast)
    }

    override func tearDown() async throws {
        immutable.forEach { RaceFixture.setImmutable($0, false) }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dbPath)
        try? FileManager.default.removeItem(at: dir)
    }

    private var dbPath: String { dir.appendingPathComponent("Dojix.sqlite").path }
    private var shotsDir: URL { dir.appendingPathComponent("Screenshots") }
    private var setAside: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.contains(".unreadable-") }
    }

    /// A journal with two trades and a screenshot; with `lockOn`, App Lock is set with
    /// `password` (key rotated, wrapped). Returns the screenshot's file.
    @discardableResult
    private func makeJournal(lockOn: Bool) throws -> URL {
        let key = try vault.createPlainKey()
        let db = try DatabaseManager(path: dbPath)
        try db.load(key: key)
        try TradeRepository(database: db).bulkInsert([SecFixture.trade(ticket: 1), SecFixture.trade(ticket: 2)])
        let shots = ScreenshotManager(baseDir: shotsDir, keyProvider: { [db] in db.currentKey })
        let name = try RaceFixture.saveScreenshot(shots)
        if lockOn {
            try KeyRotation.rotate(vault: vault, database: db, screenshots: shots, oldKey: key, password: password)
        }
        try db.unload()
        return shotsDir.appendingPathComponent("1/\(name)")
    }

    private func makeApp(hooks: DatabaseManager.Hooks = .init(), instanceLock: Bool = false) throws -> AppState {
        AppState(database: try DatabaseManager(path: dbPath, hooks: hooks), vault: vault,
                 screenshotsDirectory: shotsDir, instanceLockDirectory: instanceLock ? dir : nil)
    }

    private func trades(_ app: AppState) throws -> Int { try app.tradeRepository.count() }

    /// Lock `app` from inside the key change (off the main actor, like a lid close).
    private func lockDuringKeyChange(_ app: AppState) {
        let box = Shared<AppState?>(app)
        app.hooks.whileChangingKey = { await MainActor.run { box.value?.lock() } }
    }

    // MARK: - Finding 4: lock() when the Keychain can't be read

    func testLockLocksEvenWhenTheKeychainCannotBeReadAtThatMoment() async throws {
        try makeJournal(lockOn: true)
        let app = try makeApp()
        XCTAssertTrue(app.isLocked)
        let unlocked = await app.unlock(password: password)
        XCTAssertEqual(unlocked, .unlocked)

        store.forcedReadStatus = errSecInteractionNotAllowed
        app.lock()
        store.forcedReadStatus = nil
        XCTAssertTrue(app.isLocked, "a Keychain hiccup must not keep the decrypted journal on screen")
        XCTAssertFalse(app.database.isLoaded)
    }

    // MARK: - Locks racing Disable / Change Password / Enable

    func testDisableRacingALockNeverLeavesALockScreenThatCannotUnlock() async throws {
        try makeJournal(lockOn: true)
        let app = try makeApp()
        _ = await app.unlock(password: password)
        lockDuringKeyChange(app)

        try? await app.disableAppLock(password: password)
        app.hooks.whileChangingKey = nil

        if app.isLocked {
            let result = await app.unlock(password: password)
            XCTAssertEqual(result, .unlocked, "the lock screen must accept the password")
        }
        XCTAssertEqual(try trades(app), 2)
    }

    func testChangePasswordRacingALockKeepsTheJournalAndTheNewPasswordOpensIt() async throws {
        try makeJournal(lockOn: true)
        let app = try makeApp()
        _ = await app.unlock(password: password)
        lockDuringKeyChange(app)

        var outcome: KeyRotation.Outcome?
        do {
            outcome = try await app.changeAppLockPassword(current: password, new: newPassword)
        } catch {
            XCTFail("the new password was stored; reporting \(error) would lock the user out")
        }
        app.hooks.whileChangingKey = nil
        XCTAssertEqual(outcome, .finishesOnNextUnlock)
        XCTAssertTrue(app.isLocked)
        let result = await app.unlock(password: newPassword)
        XCTAssertEqual(result, .unlocked)
        XCTAssertEqual(try trades(app), 2)
        XCTAssertNil(try vault.unwrapKeys(password: newPassword).previous, "the next unlock finished the rotation")
    }

    func testALockRequestedWhileEnablingAppLockLocksOnceItIsOn() async throws {
        try makeJournal(lockOn: false)
        let app = try makeApp()
        XCTAssertFalse(app.isLocked)
        lockDuringKeyChange(app)

        _ = try await app.enableAppLock(password: password)
        app.hooks.whileChangingKey = nil

        XCTAssertTrue(app.isLocked, "the lid was closed while App Lock was being turned on")
        let result = await app.unlock(password: password)
        XCTAssertEqual(result, .unlocked)
        XCTAssertEqual(try trades(app), 2)
    }

    // MARK: - Finding 2: a pending rotation is finished before the key changes again

    /// App Lock on, with an unfinished rotation: the screenshot is still sealed with the
    /// previous key (it couldn't be written at the last unlock).
    private func appWithPendingRotation() async throws -> (AppState, URL) {
        let shot = try makeJournal(lockOn: false)
        let plain = try XCTUnwrap(try vault.plainKey())
        _ = try vault.beginRotation(from: plain, password: password)   // interrupted rotation
        RaceFixture.setImmutable(shot, true)
        immutable.append(shot)
        let app = try makeApp()
        let unlocked = await app.unlock(password: password)
        XCTAssertEqual(unlocked, .unlocked)
        RaceFixture.setImmutable(shot, false)
        return (app, shot)
    }

    func testChangingThePasswordWithAPendingRotationLosesNoFile() async throws {
        let (app, shot) = try await appWithPendingRotation()
        _ = try await app.changeAppLockPassword(current: password, new: newPassword)
        let keys = try vault.unwrapKeys(password: newPassword)
        let opens = [keys.current] + (keys.previous.map { [$0] } ?? [])
        XCTAssertTrue(opens.contains { RaceFixture.screenshot(at: shot, opensWith: $0) },
                      "the screenshot's key was dropped")
    }

    func testDisablingWithAPendingRotationLosesNoFile() async throws {
        let (app, shot) = try await appWithPendingRotation()
        try await app.disableAppLock(password: password)
        let plain = try XCTUnwrap(try vault.plainKey())
        XCTAssertTrue(RaceFixture.screenshot(at: shot, opensWith: plain), "the screenshot's key was dropped")
    }

    // MARK: - Opening on a full disk / with an unreadable file (from the Greenwick review)

    func testAFullDiskAtLaunchNeverSetsTheHealthyJournalAside() throws {
        try makeJournal(lockOn: false)
        let app = try makeApp(hooks: .init(willPersist: { throw POSIXError(.ENOSPC) }))
        XCTAssertFalse(app.isDatabaseFailed)
        XCTAssertEqual(setAside, [], "a journal that decrypted must never be renamed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dbPath))
        XCTAssertEqual(try trades(app), 2)
        XCTAssertNotNil(app.databaseError, "the failed save is reported")
    }

    func testAFileThatCannotBeReadIsLeftInPlace() throws {
        try makeJournal(lockOn: false)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: dbPath)
        let app = try makeApp()
        XCTAssertEqual(setAside, [], "a read error is not a damaged journal")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dbPath))
        XCTAssertTrue(app.isDatabaseFailed)
        XCTAssertFalse(app.database.isLoaded)
    }

    func testAJournalThatDoesNotDecryptIsStillSetAside() throws {
        try makeJournal(lockOn: false)
        store.delete(DatabaseKeyVault.plainAccount)
        _ = try vault.createPlainKey()   // a different key
        let app = try makeApp()
        XCTAssertEqual(setAside.count, 1)
        XCTAssertFalse(app.isDatabaseFailed)
        XCTAssertEqual(try trades(app), 0)
    }

    // MARK: - Two running copies (from the Greenwick review)

    func testASecondCopyOnTheSameDataFolderOpensNothing() throws {
        try makeJournal(lockOn: false)
        let first = try makeApp(instanceLock: true)
        XCTAssertTrue(first.database.isLoaded)

        let second = try makeApp(instanceLock: true)
        XCTAssertTrue(second.isDatabaseFailed)
        XCTAssertFalse(second.database.isLoaded)
        XCTAssertTrue(second.databaseError?.contains("already open") == true)
        XCTAssertEqual(try trades(first), 2)
    }

    func testTheFolderIsFreedWhenTheCopyHoldingItEnds() {
        var first: InstanceLock?
        if case .acquired(let lock) = InstanceLock.acquire(in: dir) { first = lock }
        XCTAssertNotNil(first)
        guard case .heldByAnotherCopy = InstanceLock.acquire(in: dir) else { return XCTFail("second copy got in") }
        first = nil   // the process ends (the kernel also drops the lock after a crash)
        guard case .acquired = InstanceLock.acquire(in: dir) else { return XCTFail("lock not released") }
    }
}
