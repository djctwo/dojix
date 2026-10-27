import AppKit
import CryptoKit
import XCTest
@testable import Dojix

/// Every Double→Int conversion in analytics is clamped (F5, Greenwick F3/F4 equivalents).
final class AnalyticsClampTests: XCTestCase {
    func testSaturatingConversion() {
        XCTAssertEqual(Int(saturating: .nan), 0)
        XCTAssertEqual(Int(saturating: .infinity), .max)
        XCTAssertEqual(Int(saturating: -.infinity), .min)
        XCTAssertEqual(Int(saturating: 1e21), .max)
        XCTAssertEqual(Int(saturating: -1e21), .min)
        XCTAssertEqual(Int(saturating: 42.9), 42)
        XCTAssertEqual(Int(saturating: -42.9), -42)
        XCTAssertEqual([Int.max, 5].saturatingSum(), .max)
        XCTAssertEqual([Int.min, -5].saturatingSum(), .min)
        XCTAssertEqual([Int.max, Int.max].saturatingAverage(), .max)
        XCTAssertEqual([Int]().saturatingAverage(), 0)
    }

    /// Lots that alternate 1e-15 after wins and 1e6 after losses (a crafted file that
    /// bypassed the import minimum, e.g. an old database) must not crash the Risk view.
    func testBehavioralScoreWithExtremeLotRatio() {
        var trades: [Trade] = []
        for i in 0..<30 {
            let isWin = i.isMultiple(of: 2)
            var t = SecFixture.trade(ticket: Int64(i), lots: isWin ? 1_000_000 : 1e-15,
                                     netProfit: isWin ? 10 : -10,
                                     closeTime: Date(timeIntervalSince1970: 1_767_225_600 + Double(i) * 7200))
            t.lots = isWin ? 1e-15 : 1_000_000 // unsanitized, as if already in the database
            trades.append(t)
        }
        let report = BehavioralAnalytics(trades: trades).report
        XCTAssertNotNil(report)
        XCTAssertTrue((0...100).contains(report?.disciplineScore ?? -1))

        // Zero lots after wins (size unknown) gives an infinite ratio: still no crash
        let zeroed = trades.map { t -> Trade in var c = t; if c.lots < 1 { c.lots = 0 }; return c }
        XCTAssertNotNil(BehavioralAnalytics(trades: zeroed).report)
    }

    /// P&L beyond Int's range must not crash the P&L distribution chart.
    func testWinLossBucketsWithHugeProfit() {
        let trades = [
            SecFixture.trade(ticket: 1, netProfit: Decimal(string: "-1e21") ?? 0),
            SecFixture.trade(ticket: 2, netProfit: Decimal(string: "1e21") ?? 0),
        ]
        XCTAssertFalse(WinLossDistribution(trades: trades).buckets.isEmpty)
    }

    func testDevelopmentOverridesIgnoredWhenNotAllowed() {
        let env = ["DOJIX_DATA_DIR": "/tmp/elsewhere", "DOJIX_KEYCHAIN_SERVICE": "x"]
        XCTAssertNil(Configuration.environmentOverride("DOJIX_DATA_DIR", environment: env, allowed: false))
        XCTAssertNil(Configuration.environmentOverride("DOJIX_KEYCHAIN_SERVICE", environment: env, allowed: false))
        XCTAssertEqual(Configuration.environmentOverride("DOJIX_DATA_DIR", environment: env, allowed: true), "/tmp/elsewhere")
        XCTAssertNil(Configuration.environmentOverride("DOJIX_DATA_DIR", environment: ["DOJIX_DATA_DIR": ""], allowed: true))
    }

    func testScreenshotNameWhitelist() {
        XCTAssertTrue(ScreenshotManager.isValidFilename("\(UUID().uuidString).jpg"))
        for bad in ["..", ".", "", ".jpg", "../x.jpg", "a/b.jpg", "\(UUID().uuidString).png",
                    ".\(UUID().uuidString).jpg", "\(UUID().uuidString).jpg/..", "x.jpg"] {
            XCTAssertFalse(ScreenshotManager.isValidFilename(bad), bad)
        }
        let manager = ScreenshotManager(baseDir: URL(fileURLWithPath: "/tmp/dojix-shots"), keyProvider: { nil })
        XCTAssertNil(manager.imageURL(filename: "..", for: 1))
        XCTAssertEqual(manager.imageURL(filename: "\(UUID().uuidString).jpg", for: 1)?.deletingLastPathComponent().path,
                       "/tmp/dojix-shots/1")
    }

    func testScreenshotsAreEncryptedOnDisk() throws {
        let dir = try SecFixture.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let key = SymmetricKey(size: .bits256)
        let manager = ScreenshotManager(baseDir: dir, keyProvider: { key })
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus(); NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 4, height: 4).fill(); image.unlockFocus()

        let name = try manager.saveImage(image, for: 1)
        let onDisk = try Data(contentsOf: dir.appendingPathComponent("1").appendingPathComponent(name))
        XCTAssertNotEqual(onDisk.prefix(2), Data([0xFF, 0xD8]), "not a readable JPEG on disk")
        XCTAssertNotNil(manager.loadImage(filename: name, for: 1))
        let locked = ScreenshotManager(baseDir: dir, keyProvider: { nil })
        XCTAssertNil(locked.loadImage(filename: name, for: 1), "unreadable without the key")

        // A plain JPEG from an older build is encrypted in place
        let legacyName = "\(UUID().uuidString).jpg"
        let legacyURL = dir.appendingPathComponent("1").appendingPathComponent(legacyName)
        try Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]).write(to: legacyURL)
        XCTAssertEqual(manager.encryptLegacyFiles(), 1)
        XCTAssertNotEqual(try Data(contentsOf: legacyURL).prefix(2), Data([0xFF, 0xD8]))
        XCTAssertEqual(manager.loadImageData(filename: legacyName, for: 1), Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]))
    }
}
