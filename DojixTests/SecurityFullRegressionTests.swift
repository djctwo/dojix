import CryptoKit
import Foundation
import os
import XCTest
@testable import Dojix

/// Regressions from a security review (export permissions, redirects, key storage). These
/// use only APIs that also exist before the fixes, so they can be run against the old code
/// to show the failure. All data is fictional.
final class SecurityFullRegressionTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = try SecFixture.scratchDirectory()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    private func permissions(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    // MARK: - Exports are owner-only, like backups

    func testCSVAndPDFExportsAreOwnerOnly() throws {
        let trades = [SecFixture.trade(ticket: 1), SecFixture.trade(ticket: 2, netProfit: -5)]
        let csv = scratch.appendingPathComponent("trades.csv")
        let pdf = scratch.appendingPathComponent("journal.pdf")
        // An existing world-readable file at the destination must not keep its mode.
        FileManager.default.createFile(atPath: csv.path, contents: Data("old".utf8),
                                       attributes: [.posixPermissions: 0o644])

        try CSVExporter().export(trades: trades, to: csv)
        try PDFExporter().exportJournal(trades: trades, metrics: MetricsCalculator.calculate(from: trades), to: pdf)

        XCTAssertEqual(try permissions(csv), 0o600, "CSV export holds trade data: owner-only")
        XCTAssertEqual(try permissions(pdf), 0o600, "PDF export holds trade data: owner-only")
        XCTAssertTrue(try String(contentsOf: csv, encoding: .utf8).hasPrefix("Ticket,Symbol"))
    }

    // MARK: - Atomic writes never follow a planted symlink

    /// A symlink at the temp name an older build always used (`<file>.saving`), made
    /// immutable so it can't simply be deleted first, like a link another user owns in a
    /// shared folder such as /tmp. Writing must not go through it.
    func testSymlinkAtAPredictableTempNameIsNeverFollowed() throws {
        let victim = scratch.appendingPathComponent("victim.txt")
        try Data("keep me".utf8).write(to: victim)
        let writers: [(String, (URL) throws -> Void)] = [
            ("csv export", { try CSVExporter().export(trades: [SecFixture.trade(ticket: 1)], to: $0) }),
            ("sealed journal", { try DatabaseEncryption.writeAtomically(Data("sealed".utf8), to: $0.path) }),
            ("backup", { try BackupService.writeBackup(of: try DatabaseManager(inMemory: true), to: $0) }),
        ]
        for (name, write) in writers {
            let destination = scratch.appendingPathComponent("\(UUID().uuidString).out")
            let planted = destination.path + ".saving"
            XCTAssertEqual(symlink(victim.path, planted), 0)
            XCTAssertEqual(lchflags(planted, UInt32(UF_IMMUTABLE)), 0)
            defer { lchflags(planted, 0); unlink(planted) }

            try? write(destination)

            XCTAssertEqual(try String(contentsOf: victim, encoding: .utf8), "keep me", "\(name) wrote through the link")
            let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path)
            XCTAssertEqual(attributes?[.type] as? FileAttributeType, .typeRegular, name)
            XCTAssertEqual((attributes?[.posixPermissions] as? NSNumber)?.intValue, 0o600, name)
        }
    }

    /// A symlink at the destination itself is replaced, never written through.
    func testSymlinkAtTheDestinationIsReplacedNotFollowed() throws {
        let victim = scratch.appendingPathComponent("victim.txt")
        try Data("keep me".utf8).write(to: victim)
        let destination = scratch.appendingPathComponent("journal.pdf")
        XCTAssertEqual(symlink(victim.path, destination.path), 0)

        try OwnerOnlyFile.write(Data("report".utf8), to: destination)

        XCTAssertEqual(try String(contentsOf: victim, encoding: .utf8), "keep me")
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "report")
        XCTAssertEqual(try permissions(destination), 0o600)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: scratch.path).filter { $0.hasSuffix(".saving") }
        XCTAssertEqual(leftovers, [], "no temp file is left behind")
    }

    // MARK: - Locking never drops a commit that raced it

    /// Every insert that reported success before the lock must be in the saved journal.
    /// (A race: this can only fail sometimes on code with the bug, never on fixed code.)
    func testUnloadKeepsEveryCommitThatRacedIt() throws {
        let key = SymmetricKey(size: .bits256)
        let path = scratch.appendingPathComponent("Dojix.sqlite").path
        let journal = try DatabaseManager(path: path)
        let committed = OSAllocatedUnfairLock(initialState: 0)
        var nextTicket: Int64 = 1
        for _ in 0..<40 {
            try journal.load(key: key)
            let repository = TradeRepository(database: journal)
            let start = nextTicket
            let done = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                var ticket = start
                while (try? repository.insertIfNew(SecFixture.trade(ticket: ticket))) == true {
                    committed.withLock { $0 += 1 }
                    ticket += 1
                }
                done.signal()
            }
            usleep(useconds_t.random(in: 200...3_000))
            try journal.unload()
            done.wait()
            nextTicket = start + 100_000
        }
        try journal.load(key: key)
        XCTAssertEqual(try TradeRepository(database: journal).count(), committed.withLock { $0 })
    }

    // MARK: - Costs typed by hand stay inside what a restore accepts

    func testHugeCostsAreClampedSoDojixsOwnBackupRestores() throws {
        let database = try DatabaseManager(inMemory: true)
        let repository = TradeRepository(database: database)
        try repository.insertIfNew(SecFixture.trade(ticket: 7))
        let id = try XCTUnwrap(try repository.fetchAll().first?.id)

        let commission = try XCTUnwrap(Decimal(string: "5e15"))
        let swap = try XCTUnwrap(Decimal(string: "-7e20"))
        try repository.updateCosts(tradeId: id, commission: commission, swap: swap)

        let stored = try XCTUnwrap(try repository.fetchAll().first)
        XCTAssertEqual(stored.storageViolations(), [])
        XCTAssertEqual(stored.commission, Trade.moneyLimit)
        XCTAssertEqual(stored.swap, -Trade.moneyLimit)

        // A backup Dojix writes must be one Dojix can restore.
        let backup = scratch.appendingPathComponent("backup.dojix")
        try BackupService.writeBackup(of: database, to: backup)
        XCTAssertNoThrow(try BackupService.validatedContents(of: backup))
    }

    // MARK: - MT5 price file is size-capped

    private func priceUpdates(fromFileWith contents: String) async throws -> [PriceUpdate] {
        try contents.write(to: scratch.appendingPathComponent("DojixPrices.json"), atomically: true, encoding: .utf8)
        let provider = MT5FileProvider(mt5Path: scratch.path)
        try await provider.subscribe(symbols: [])
        await provider.disconnect()
        var updates: [PriceUpdate] = []
        for await update in provider.prices { updates.append(update) }
        return updates
    }

    private let priceJSON = #"{"ts":"2026.01.01 10:00:00","prices":[{"s":"EURUSD","b":1.1,"a":1.1002}]}"#

    func testNormalPriceFileIsRead() async throws {
        let updates = try await priceUpdates(fromFileWith: priceJSON)
        XCTAssertEqual(updates.map(\.symbol), ["EURUSD"])
    }

    /// Any MQL5 program can write to MT5's Files folders; a huge file must not be loaded
    /// into memory on every change.
    func testOversizedPriceFileIsIgnored() async throws {
        let padded = priceJSON + String(repeating: " ", count: 2 * 1024 * 1024)
        let updates = try await priceUpdates(fromFileWith: padded)
        XCTAssertTrue(updates.isEmpty, "a price file over the size cap is not parsed")
    }

    // MARK: - API credentials never follow a redirect to another host

    private final class Decision: @unchecked Sendable {
        var called = false
        var request: URLRequest?
    }

    private func redirectDecision(from: String, to: String) throws -> URLRequest? {
        let session = SecureSession.make()
        defer { session.invalidateAndCancel() }
        guard let delegate = session.delegate as? URLSessionTaskDelegate else {
            XCTFail("SecureSession has no redirect policy (delegate)")
            return nil
        }
        let original = URLRequest(url: try XCTUnwrap(URL(string: from)))
        var next = URLRequest(url: try XCTUnwrap(URL(string: to)))
        next.setValue("Bearer fictional-token", forHTTPHeaderField: "Authorization")
        next.setValue("fictional-key", forHTTPHeaderField: "x-api-key")
        let task = session.dataTask(with: original)
        defer { task.cancel() }
        let response = try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(original.url), statusCode: 302,
                                                     httpVersion: "HTTP/1.1", headerFields: ["Location": to]))
        let decision = Decision()
        let decided = expectation(description: "redirect decision")
        delegate.urlSession?(session, task: task, willPerformHTTPRedirection: response, newRequest: next) { request in
            decision.called = true
            decision.request = request
            decided.fulfill()
        }
        wait(for: [decided], timeout: 5)
        XCTAssertTrue(decision.called, "the redirect policy must decide")
        return decision.request
    }

    func testRedirectToAnotherHostIsRefused() throws {
        XCTAssertNil(try redirectDecision(from: "https://api-fxtrade.oanda.com/v3/accounts/1/transactions",
                                          to: "https://collector.example/steal"))
        XCTAssertNil(try redirectDecision(from: "https://api.anthropic.com/v1/messages",
                                          to: "https://api.anthropic.com.example/v1/messages"))
    }

    func testRedirectToPlainHTTPIsRefused() throws {
        XCTAssertNil(try redirectDecision(from: "https://api.polygon.io/v2/last/nbbo/C:EURUSD",
                                          to: "http://api.polygon.io/v2/last/nbbo/C:EURUSD"))
    }

    func testSameHostHTTPSRedirectIsFollowed() throws {
        let request = try redirectDecision(from: "https://api.twelvedata.com/quote",
                                           to: "https://API.twelvedata.com/v2/quote")
        XCTAssertEqual(request?.url?.path, "/v2/quote")
    }

    // MARK: - Legacy API key copy in UserDefaults

    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suite = "com.dojix.tests.secfull.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return XCTFail("no defaults suite") }
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    /// The Keychain already holds a key: the plaintext copy in the preferences file must
    /// still be removed (it used to stay there forever).
    func testLegacyDefaultsKeyIsRemovedWhenKeychainAlreadyHasOne() {
        withDefaults { defaults in
            defaults.set("fictional-old-key", forKey: "anthropic_api_key")
            var saved: [String] = []
            KeychainHelper.migrateFromUserDefaults(defaults: defaults,
                                                   read: { _ in "fictional-current-key" },
                                                   save: { _, value in saved.append(value); return true })
            XCTAssertNil(defaults.string(forKey: "anthropic_api_key"))
            XCTAssertEqual(saved, [], "the newer Keychain key is not overwritten")
        }
    }

    /// The Keychain refused the key: keep the only copy rather than lose it.
    func testLegacyDefaultsKeyIsKeptWhenKeychainSaveFails() {
        withDefaults { defaults in
            defaults.set("fictional-old-key", forKey: "anthropic_api_key")
            KeychainHelper.migrateFromUserDefaults(defaults: defaults, read: { _ in nil }, save: { _, _ in false })
            XCTAssertEqual(defaults.string(forKey: "anthropic_api_key"), "fictional-old-key")
        }
    }

    func testLegacyDefaultsKeyMovesToKeychain() {
        withDefaults { defaults in
            defaults.set("fictional-old-key", forKey: "anthropic_api_key")
            var saved: [String: String] = [:]
            KeychainHelper.migrateFromUserDefaults(defaults: defaults, read: { _ in nil },
                                                   save: { account, value in saved[account] = value; return true })
            XCTAssertEqual(saved, ["anthropic_api_key": "fictional-old-key"])
            XCTAssertNil(defaults.string(forKey: "anthropic_api_key"))
        }
    }
}
