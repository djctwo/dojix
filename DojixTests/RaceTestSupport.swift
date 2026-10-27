import AppKit
import CryptoKit
import Darwin
import Foundation
import XCTest
@testable import Dojix

/// Helpers that make races deterministic: the code under test is stopped at a named
/// point (a hook) and released by the test, never timed with sleeps. The timeouts only
/// keep a broken build from hanging the suite.
final class Signal: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)

    func fire() { semaphore.signal() }

    /// Wait for `fire()`; fails the test (instead of hanging) if it never comes.
    func wait(_ what: String, file: StaticString = #filePath, line: UInt = #line) {
        if semaphore.wait(timeout: .now() + 30) == .timedOut {
            XCTFail("timed out waiting for: \(what)", file: file, line: line)
        }
    }
}

/// A value shared with hooks that run on other threads.
final class Shared<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); defer { lock.unlock() }; stored = newValue }
    }

    /// Returns the current value and replaces it (atomically).
    func exchange(_ newValue: Value) -> Value {
        lock.lock(); defer { lock.unlock() }
        let old = stored
        stored = newValue
        return old
    }
}

enum RaceFixture {
    /// Run `work` on a background thread; the returned signal fires when it is done.
    static func inBackground(_ work: @escaping @Sendable () -> Void) -> Signal {
        let done = Signal()
        Thread.detachNewThread {
            work()
            done.fire()
        }
        return done
    }

    /// A small screenshot saved for trade 1.
    static func saveScreenshot(_ shots: ScreenshotManager) throws -> String {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus(); NSColor.blue.setFill(); NSRect(x: 0, y: 0, width: 2, height: 2).fill(); image.unlockFocus()
        return try shots.saveImage(image, for: 1)
    }

    /// Whether the sealed screenshot file opens with `key`.
    static func screenshot(at url: URL, opensWith key: SymmetricKey) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        return (try? DatabaseEncryption.open(data.dropFirst(4), key: key)) != nil
    }

    /// Make a file immutable (`uchg`) so it can't be replaced, or mutable again.
    static func setImmutable(_ url: URL, _ immutable: Bool) {
        _ = chflags(url.path, immutable ? UInt32(UF_IMMUTABLE) : 0)
    }

    /// A database image with Dojix's schema and `trades` sample trades (for restores).
    static func journalImage(trades: Int) throws -> Data {
        let source = try DatabaseManager(inMemory: true)
        try TradeRepository(database: source).bulkInsert((0..<trades).map { SecFixture.trade(ticket: Int64(100 + $0)) })
        return try source.dbQueue.writeWithoutTransaction { try DatabaseManager.serialize($0) }
    }
}

/// Stand-in for `AppState` in Settings tests.
@MainActor
final class FakeAppLock: AppLockActions {
    var isAppLockOn = false
    var calls = 0
    /// What the next enable/change/disable does.
    var result: () throws -> KeyRotation.Outcome = { .complete }
    /// Lock state after the call (whatever happens).
    var lockOnAfterCall: Bool?

    func enableAppLock(password: String) async throws -> KeyRotation.Outcome { try perform() }
    func changeAppLockPassword(current: String, new: String) async throws -> KeyRotation.Outcome { try perform() }
    func disableAppLock(password: String) async throws { _ = try perform() }

    private func perform() throws -> KeyRotation.Outcome {
        calls += 1
        defer { if let lockOnAfterCall { isAppLockOn = lockOnAfterCall } }
        return try result()
    }
}
