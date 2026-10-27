import CryptoKit
import Security
import XCTest
@testable import Dojix

/// Fixes from the re-review (N1–N8): erase and locks racing key operations, folders that
/// can't be listed during a key rotation, a screenshot saved during the re-seal, a
/// Keychain read-back error after the new key was stored, a restore whose save fails, and
/// "Quit & Relaunch" with the single-instance lock. Scratch folders and in-memory key
/// stores only.
@MainActor
final class RereviewFixTests: XCTestCase {
    private let fast: UInt32 = 1_000
    private let password = "fictional-lock-pw"
    private let newPassword = "new-fictional-pw"
    private var dir: URL!
    private var store: MemorySecretStore!
    private var vault: DatabaseKeyVault!
    private var restorePermissions: [URL] = []

    override func setUp() async throws {
        dir = try SecFixture.scratchDirectory()
        store = MemorySecretStore()
        vault = DatabaseKeyVault(store: store, iterations: fast)
    }

    override func tearDown() async throws {
        for url in restorePermissions {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        }
        try? FileManager.default.removeItem(at: dir)
    }

    private var dbPath: String { dir.appendingPathComponent("Dojix.sqlite").path }
    private var shotsDir: URL { dir.appendingPathComponent("Screenshots") }

    /// Two trades and a screenshot, sealed with a bare key; with `lockOn`, App Lock is
    /// set with `password`. Returns the loaded journal, its screenshots and the key in use.
    private func makeJournal(lockOn: Bool, hooks: DatabaseManager.Hooks = .init())
        throws -> (DatabaseManager, ScreenshotManager, SymmetricKey) {
        let key = try vault.createPlainKey()
        let db = try DatabaseManager(path: dbPath, hooks: hooks)
        try db.load(key: key)
        try TradeRepository(database: db).bulkInsert([SecFixture.trade(ticket: 1), SecFixture.trade(ticket: 2)])
        let shots = ScreenshotManager(baseDir: shotsDir, keyProvider: { [db] in db.currentKey })
        _ = try RaceFixture.saveScreenshot(shots)
        if lockOn {
            try KeyRotation.rotate(vault: vault, database: db, screenshots: shots, oldKey: key, password: password)
        }
        return (db, shots, db.currentKey ?? key)
    }

    private func makeApp(instanceLock: Bool = false) throws -> AppState {
        AppState(database: try DatabaseManager(path: dbPath), vault: vault, screenshotsDirectory: shotsDir,
                 instanceLockDirectory: instanceLock ? dir : nil)
    }

    private func unreadable(_ url: URL, mode: Int = 0) throws {
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
        restorePermissions.append(url)
    }

    /// Lets every job already queued on the main actor run (the main queue is FIFO).
    private func drainMainActor() async {
        await Task { @MainActor in }.value
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

    // MARK: - N4: "Erase Everything" waits for key operations still running

    func testEraseDuringAPasswordChangeLeavesTheNewJournalWithItsOwnStoredKey() async throws {
        let (db, _, _) = try makeJournal(lockOn: true)
        try db.unload()
        let app = try makeApp()
        _ = await app.unlock(password: password)
        let reached = Signal(), release = Signal()
        app.hooks.whileChangingKey = { reached.fire(); release.wait("release the password change") }

        let change = Task { @MainActor in try await app.changeAppLockPassword(current: password, new: newPassword) }
        await waitOffMain(reached, "password change in progress")
        app.lock()   // lid closed; then "Forgot Password?" on the lock screen
        let erase = Task { @MainActor in try await app.eraseAllAndStartFresh() }
        await drainMainActor()
        release.fire()
        _ = try? await change.value
        try await erase.value

        XCTAssertEqual(try vault.state(), .plain, "the erase starts a journal without App Lock")
        let key = try XCTUnwrap(try vault.plainKey())
        XCTAssertTrue(KeyRotation.journalOpens(at: dbPath, with: key), "the new journal is sealed with a key that isn't stored")
        XCTAssertFalse(app.isAppLockOn)
        XCTAssertFalse(app.isLocked)
    }

    func testEraseDuringAnUnlockNeverLeavesALockScreenThatRejectsEveryPassword() async throws {
        let (db, _, _) = try makeJournal(lockOn: true)
        try db.unload()
        let app = try makeApp()
        let reached = Signal(), release = Signal()
        app.hooks.whileUnlocking = { reached.fire(); release.wait("release the unlock") }

        let unlock = Task { @MainActor in await app.unlock(password: password) }
        await waitOffMain(reached, "unlock in progress")
        let erase = Task { @MainActor in try await app.eraseAllAndStartFresh() }
        await drainMainActor()
        release.fire()
        _ = await unlock.value
        try await erase.value
        app.hooks.whileUnlocking = nil

        XCTAssertEqual(try vault.state(), .plain)
        XCTAssertFalse(app.isAppLockOn, "App Lock 'on' with a bare key: the lock screen could never be passed")
        XCTAssertTrue(KeyRotation.journalOpens(at: dbPath, with: try XCTUnwrap(try vault.plainKey())))
    }

    // MARK: - N5: a lock requested during an unlock is carried out

    func testALockRequestedDuringAnUnlockLocksOnceTheUnlockEnds() async throws {
        let (db, _, _) = try makeJournal(lockOn: true)
        try db.unload()
        let app = try makeApp()
        let box = Shared<AppState?>(app)
        app.hooks.whileUnlocking = { await MainActor.run { box.value?.lock() } }

        _ = await app.unlock(password: password)
        app.hooks.whileUnlocking = nil

        XCTAssertTrue(app.isLocked, "the lid was closed while the password was being checked")
        XCTAssertFalse(app.database.isLoaded)
        let result = await app.unlock(password: password)
        XCTAssertEqual(result, .unlocked)
        XCTAssertEqual(try app.tradeRepository.count(), 2)
    }

    // MARK: - N2: a folder that can't be listed counts as pending

    func testAScreenshotFolderThatCannotBeListedKeepsTheOldKey() throws {
        let (db, shots, oldKey) = try makeJournal(lockOn: false)
        try unreadable(shotsDir.appendingPathComponent("1"))

        let outcome = try KeyRotation.rotate(vault: vault, database: db, screenshots: shots, oldKey: oldKey, password: password)

        XCTAssertEqual(outcome, .finishesOnNextUnlock)
        XCTAssertNotNil(try vault.unwrapKeys(password: password).previous, "the screenshots' key was dropped")
    }

    func testADataFolderThatCannotBeListedKeepsTheOldKey() throws {
        let (db, shots, oldKey) = try makeJournal(lockOn: false)
        try unreadable(dir, mode: 0o300)   // files can still be opened and replaced by name

        let outcome = try KeyRotation.rotate(vault: vault, database: db, screenshots: shots, oldKey: oldKey, password: password)

        XCTAssertEqual(outcome, .finishesOnNextUnlock)
        XCTAssertNotNil(try vault.unwrapKeys(password: password).previous, "journal copies' key was dropped")
    }

    // MARK: - N3: a screenshot saved while the re-seal starts is re-sealed too

    func testAScreenshotBeingSavedWhenTheResealStartsIsResealed() throws {
        let old = SymmetricKey(size: .bits256), new = SymmetricKey(size: .bits256)
        let key = Shared(old)
        let inWrite = Signal(), release = Signal()
        let shots = ScreenshotManager(baseDir: shotsDir, keyProvider: { key.value },
                                      willSaveImage: { inWrite.fire(); release.wait("release the save") })
        let name = Shared<String?>(nil)
        let saved = RaceFixture.inBackground { name.value = try? RaceFixture.saveScreenshot(shots) }
        inWrite.wait("screenshot save holding the old key")
        key.value = new   // the journal was re-keyed
        let pending = Shared<[URL]>([])
        let resealed = RaceFixture.inBackground { pending.value = shots.reseal(from: old, to: new) }
        release.fire()
        saved.wait("save")
        resealed.wait("re-seal")

        let file = shotsDir.appendingPathComponent("1/\(try XCTUnwrap(name.value))")
        XCTAssertTrue(RaceFixture.screenshot(at: file, opensWith: new) || pending.value.contains(file),
                      "the screenshot would be lost when the old key is dropped")
    }

    // MARK: - N6: a read-back error after the new key was stored

    func testAReadBackErrorAfterTheNewKeyWasStoredStillCountsAsChanged() throws {
        let (db, shots, oldKey) = try makeJournal(lockOn: false)
        let flaky = FlakyReadBackStore(store)
        let flakyVault = DatabaseKeyVault(store: flaky, iterations: fast)
        flaky.failNextReadAfterWrite = true

        var outcome: KeyRotation.Outcome?
        XCTAssertNoThrow(outcome = try KeyRotation.rotate(vault: flakyVault, database: db, screenshots: shots,
                                                          oldKey: oldKey, password: password),
                         "the Keychain stored the new password; reporting a failure misleads the user")
        XCTAssertEqual(outcome, .finishesOnNextUnlock)
        try db.unload()
        // The next unlock (new password) opens the journal and finishes the change.
        let keys = try AppState.unlockKeys(vault: vault, password: password, legacyHash: nil)
        let reopened = try DatabaseManager(path: dbPath)
        try reopened.load(key: keys.current, previousKey: keys.previous)
        XCTAssertEqual(try TradeRepository(database: reopened).count(), 2)
    }

    // MARK: - N7: a restore whose save fails puts the previous contents back

    func testARestoreWhoseSaveFailsKeepsThePreviousJournal() throws {
        let failing = Shared(false)
        let (db, _, key) = try makeJournal(lockOn: false, hooks: .init(willPersist: {
            if failing.value { throw POSIXError(.ENOSPC) }
        }))
        let backup = try RaceFixture.journalImage(trades: 5)
        failing.value = true

        XCTAssertThrowsError(try db.replaceContents(with: backup))
        XCTAssertEqual(try TradeRepository(database: db).count(), 2, "the restore was reported as failed")
        failing.value = false
        db.flush()
        try db.unload()
        let reopened = try DatabaseManager(path: dbPath)
        try reopened.load(key: key)
        XCTAssertEqual(try TradeRepository(database: reopened).count(), 2)
    }

    // MARK: - N8: "Quit & Relaunch" frees the data folder for the new copy

    func testRelaunchingFromTheFailureScreenLetsTheNewCopyIn() throws {
        _ = try makeJournal(lockOn: false)
        store.forcedReadStatus = errSecInteractionNotAllowed   // Keychain unreadable at launch
        let app = try makeApp(instanceLock: true)
        store.forcedReadStatus = nil
        XCTAssertTrue(app.isDatabaseFailed)
        guard case .heldByAnotherCopy = InstanceLock.acquire(in: dir) else { return XCTFail("folder not held") }

        app.releaseDataFolderForRelaunch()

        guard case .acquired = InstanceLock.acquire(in: dir) else {
            return XCTFail("the relaunched copy would say \"Dojix is already open\"")
        }
    }

    // MARK: - (Greenwick cross-check) a Keychain error is never "no lock"

    /// An older build's App Lock (bare key plus a password hash), read through `failing`.
    private func legacyLock() throws -> FailingAccountStore {
        _ = try vault.createPlainKey()
        store.write(DatabaseKeyVault.legacyHashAccount, PasswordHasher.hash(password))
        let failing = FailingAccountStore(store, account: DatabaseKeyVault.legacyHashAccount)
        vault = DatabaseKeyVault(store: failing, iterations: fast)
        return failing
    }

    func testAnUnreadableLegacyLockNeverOpensTheJournalWithoutThePassword() async throws {
        let failing = try legacyLock()
        failing.isFailing = true

        let app = try makeApp()
        XCTAssertFalse(app.database.isLoaded, "a Keychain error was taken as \"App Lock off\"")
        XCTAssertTrue(AppLock.isEnabled(vault: vault))

        failing.isFailing = false   // relaunch once the Keychain answers
        let relaunched = try makeApp()
        XCTAssertTrue(relaunched.isLocked)
        let result = await relaunched.unlock(password: password)
        XCTAssertEqual(result, .unlocked)
    }

    func testAnUnlockThatCannotReadTheLegacyLockFailsInsteadOfCountingAWrongPassword() async throws {
        let failing = try legacyLock()
        let app = try makeApp()
        XCTAssertTrue(app.isLocked)

        failing.isFailing = true
        let result = await app.unlock(password: password)
        guard case .failed = result else { return XCTFail("got \(result)") }
        XCTAssertFalse(app.database.isLoaded)
    }

    // MARK: - N1: the save record never shows a Keychain dialog

    func testTheSaveRecordIsWrittenWithoutKeychainDialogs() throws {
        let store = try XCTUnwrap(SaveGenerationStore().store as? KeychainSecretStore)
        XCTAssertFalse(store.allowsUserInteraction,
                       "a dialog on the main thread would keep the journal on screen instead of locking")
        // And such a write still works (Keychain of this test run's own service): add, then update.
        let generations = SaveGenerationStore()
        defer { generations.delete() }
        for generation: UInt64 in [1, 2] {
            let stamp = JournalStamp(epoch: JournalStamp.newEpoch(), generation: generation, savedAt: Date())
            let record = SaveRecord(stamp: stamp, sealedFile: Data("fictional \(generation)".utf8))
            XCTAssertTrue(generations.record(record))
            XCTAssertEqual(generations.lastSaved(), record)
        }
    }
}

/// A store whose reads of one account fail (a Keychain error, not "no such item").
private final class FailingAccountStore: SecretStore, @unchecked Sendable {
    private let inner: MemorySecretStore
    private let account: String
    private let failing = Shared(false)

    init(_ inner: MemorySecretStore, account: String) {
        self.inner = inner
        self.account = account
    }

    var isFailing: Bool {
        get { failing.value }
        set { failing.value = newValue }
    }

    func read(_ account: String) -> (value: String?, status: OSStatus) {
        account == self.account && isFailing ? (nil, errSecInteractionNotAllowed) : inner.read(account)
    }

    @discardableResult
    func write(_ account: String, _ value: String) -> Bool { inner.write(account, value) }
    func delete(_ account: String) { inner.delete(account) }
}

/// A store whose first read after a write fails (a transient Keychain error).
private final class FlakyReadBackStore: SecretStore, @unchecked Sendable {
    private let inner: MemorySecretStore
    private let lock = NSLock()
    private var armed = false
    private var failNext = false

    init(_ inner: MemorySecretStore) { self.inner = inner }

    var failNextReadAfterWrite: Bool {
        get { lock.withLock { armed } }
        set { lock.withLock { armed = newValue } }
    }

    func read(_ account: String) -> (value: String?, status: OSStatus) {
        let fail = lock.withLock { () -> Bool in
            defer { failNext = false }
            return failNext
        }
        return fail ? (nil, errSecInteractionNotAllowed) : inner.read(account)
    }

    @discardableResult
    func write(_ account: String, _ value: String) -> Bool {
        let ok = inner.write(account, value)
        lock.withLock {
            if armed { failNext = true; armed = false }
        }
        return ok
    }

    func delete(_ account: String) { inner.delete(account) }
}
