import XCTest
@testable import Dojix

/// "Forgot password" must erase data, never just remove the lock.
final class LocalDataEraserTests: XCTestCase {
    func testEraseRemovesTradesScreenshotsAndKeys() throws {
        let db = try DatabaseManager(inMemory: true)
        let repo = TradeRepository(database: db)
        try repo.bulkInsert(DemoDataGenerator.generateTrades())
        XCTAssertEqual(try repo.count(), 30)

        let shots = URL(fileURLWithPath: NSTemporaryDirectory() + "dojix_shots_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
        KeychainHelper.save(key: "app_lock_password_hash_test", value: "x")

        try LocalDataEraser.eraseAll(database: db, screenshotsDirectory: shots)

        XCTAssertEqual(try repo.count(), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: shots.path))
        XCTAssertNil(KeychainHelper.read(key: "app_lock_password_hash_test"))
    }
}
