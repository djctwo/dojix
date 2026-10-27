import XCTest
import GRDB
@testable import Dojix

final class TradeRepositoryTests: XCTestCase {

    private var database: DatabaseManager!
    private var repository: TradeRepository!

    override func setUp() async throws {
        // Use in-memory database for testing
        database = try DatabaseManager(inMemory: true)
        repository = TradeRepository(database: database)
    }

    // MARK: - Test Helpers

    private func makeTrade(
        ticket: Int64 = 100001,
        symbol: String = "GBPUSD",
        netProfit: Decimal = 50,
        session: TradingSession = .london,
        closeTime: Date = Date(),
        hour: Int = 10,
        tags: String = "",
        notes: String = ""
    ) -> Trade {
        Trade(
            id: nil, ticket: ticket, symbol: symbol, direction: .buy,
            lots: 0.10, openTime: closeTime.addingTimeInterval(-3600),
            closeTime: closeTime, durationMin: 60,
            openPrice: 1.25, closePrice: 1.26, sl: 1.24, tp: 1.27,
            netProfit: netProfit, maePips: 5.0, mfePips: 10.0,
            rMultiple: 1.5, session: session, dayOfWeek: "Mon", hour: hour,
            rangeSize: 40, sweepDepth: 10, usedFVG: false, volRegime: .med,
            hitBreakeven: false, scaledIn: false, magic: 12345, comment: "",
            timeToMFEMin: 30, slDistPips: 20, slippagePips: 0.5,
            postClose15m: 5, postClose30m: 10, biasAtEntry: .with,
            notes: notes, tags: tags, importedAt: Date()
        )
    }

    // MARK: - Insert

    func testInsertIfNew() throws {
        let trade = makeTrade()
        let inserted = try repository.insertIfNew(trade)
        XCTAssertTrue(inserted)

        let count = try repository.count()
        XCTAssertEqual(count, 1)
    }

    func testInsertIfNewSkipsDuplicate() throws {
        let trade = makeTrade(ticket: 100001)
        let first = try repository.insertIfNew(trade)
        XCTAssertTrue(first)

        let second = try repository.insertIfNew(trade)
        XCTAssertFalse(second)

        XCTAssertEqual(try repository.count(), 1)
    }

    func testBulkInsert() throws {
        let trades = [
            makeTrade(ticket: 1),
            makeTrade(ticket: 2),
            makeTrade(ticket: 3),
        ]
        let count = try repository.bulkInsert(trades)
        XCTAssertEqual(count, 3)
        XCTAssertEqual(try repository.count(), 3)
    }

    func testBulkInsertSkipsDuplicates() throws {
        try repository.insertIfNew(makeTrade(ticket: 2))

        let trades = [
            makeTrade(ticket: 1),
            makeTrade(ticket: 2), // duplicate
            makeTrade(ticket: 3),
        ]
        let count = try repository.bulkInsert(trades)
        XCTAssertEqual(count, 2)
        XCTAssertEqual(try repository.count(), 3)
    }

    // MARK: - Read

    func testFetchAll() throws {
        _ = try repository.bulkInsert([
            makeTrade(ticket: 1, closeTime: Date().addingTimeInterval(-200)),
            makeTrade(ticket: 2, closeTime: Date().addingTimeInterval(-100)),
            makeTrade(ticket: 3, closeTime: Date()),
        ])

        let trades = try repository.fetchAll()
        XCTAssertEqual(trades.count, 3)
        // Should be ordered by closeTime DESC
        XCTAssertEqual(trades[0].ticket, 3)
        XCTAssertEqual(trades[1].ticket, 2)
        XCTAssertEqual(trades[2].ticket, 1)
    }

    func testFetchBySymbol() throws {
        _ = try repository.bulkInsert([
            makeTrade(ticket: 1, symbol: "GBPUSD"),
            makeTrade(ticket: 2, symbol: "EURUSD"),
            makeTrade(ticket: 3, symbol: "GBPUSD"),
        ])

        let gbp = try repository.fetchBySymbol("GBPUSD")
        XCTAssertEqual(gbp.count, 2)

        let eur = try repository.fetchBySymbol("EURUSD")
        XCTAssertEqual(eur.count, 1)
    }

    func testFetchBySession() throws {
        _ = try repository.bulkInsert([
            makeTrade(ticket: 1, session: .london),
            makeTrade(ticket: 2, session: .asian),
            makeTrade(ticket: 3, session: .london),
        ])

        let london = try repository.fetchBySession(.london)
        XCTAssertEqual(london.count, 2)

        let asian = try repository.fetchBySession(.asian)
        XCTAssertEqual(asian.count, 1)
    }

    func testFetchByDateRange() throws {
        let now = Date()
        _ = try repository.bulkInsert([
            makeTrade(ticket: 1, closeTime: now.addingTimeInterval(-86400 * 5)),
            makeTrade(ticket: 2, closeTime: now.addingTimeInterval(-86400 * 2)),
            makeTrade(ticket: 3, closeTime: now),
        ])

        let trades = try repository.fetchByDateRange(
            from: now.addingTimeInterval(-86400 * 3),
            to: now
        )
        XCTAssertEqual(trades.count, 2) // ticket 2 and 3
    }

    func testTicketExists() throws {
        try repository.insertIfNew(makeTrade(ticket: 99999))

        XCTAssertTrue(try repository.ticketExists(99999))
        XCTAssertFalse(try repository.ticketExists(11111))
    }

    // MARK: - Delete

    func testDeleteAll() throws {
        _ = try repository.bulkInsert([
            makeTrade(ticket: 1),
            makeTrade(ticket: 2),
        ])
        XCTAssertEqual(try repository.count(), 2)

        try repository.deleteAll()
        XCTAssertEqual(try repository.count(), 0)
    }

    // MARK: - Update

    func testUpdateNotes() throws {
        var trade = makeTrade(ticket: 1)
        try repository.insertIfNew(trade)
        trade = try repository.fetchAll()[0]

        try repository.updateNotes(tradeId: trade.id!, notes: "Great trade setup")
        let updated = try repository.fetchAll()[0]
        XCTAssertEqual(updated.notes, "Great trade setup")
    }

    func testUpdateTags() throws {
        var trade = makeTrade(ticket: 1)
        try repository.insertIfNew(trade)
        trade = try repository.fetchAll()[0]

        try repository.updateTags(tradeId: trade.id!, tags: "sniper,setup-A")
        let updated = try repository.fetchAll()[0]
        XCTAssertEqual(updated.tags, "sniper,setup-A")
    }

    // MARK: - Aggregates

    func testTotalProfit() throws {
        _ = try repository.bulkInsert([
            makeTrade(ticket: 1, netProfit: 100),
            makeTrade(ticket: 2, netProfit: -30),
            makeTrade(ticket: 3, netProfit: 50),
        ])

        let total = try repository.totalProfit()
        XCTAssertEqual(total, 120.0, accuracy: 0.01)
    }

    func testProfitBySymbol() throws {
        _ = try repository.bulkInsert([
            makeTrade(ticket: 1, symbol: "GBPUSD", netProfit: 100),
            makeTrade(ticket: 2, symbol: "GBPUSD", netProfit: -30),
            makeTrade(ticket: 3, symbol: "EURUSD", netProfit: 50),
        ])

        let bySymbol = try repository.profitBySymbol()
        XCTAssertEqual(bySymbol.count, 2)

        let gbp = bySymbol.first { $0.symbol == "GBPUSD" }
        XCTAssertNotNil(gbp)
        XCTAssertEqual(gbp?.profit ?? 0, 70.0, accuracy: 0.01)
        XCTAssertEqual(gbp?.count, 2)
    }

    func testProfitBySession() throws {
        _ = try repository.bulkInsert([
            makeTrade(ticket: 1, netProfit: 100, session: .london),
            makeTrade(ticket: 2, netProfit: -30, session: .asian),
        ])

        let bySession = try repository.profitBySession()
        XCTAssertEqual(bySession.count, 2)
    }

    func testEquityCurve() throws {
        let now = Date()
        _ = try repository.bulkInsert([
            makeTrade(ticket: 1, netProfit: 100, closeTime: now.addingTimeInterval(-200)),
            makeTrade(ticket: 2, netProfit: -30, closeTime: now.addingTimeInterval(-100)),
            makeTrade(ticket: 3, netProfit: 50, closeTime: now),
        ])

        let curve = try repository.equityCurve()
        XCTAssertEqual(curve.count, 3)
        XCTAssertEqual(curve[0].cumulative, 100.0, accuracy: 0.01)
        XCTAssertEqual(curve[1].cumulative, 70.0, accuracy: 0.01)
        XCTAssertEqual(curve[2].cumulative, 120.0, accuracy: 0.01)
    }
}
