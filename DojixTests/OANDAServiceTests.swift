import XCTest
@testable import Dojix

final class OANDAServiceTests: XCTestCase {

    // MARK: - OANDAError Descriptions

    func testInvalidURLErrorHasDescription() {
        let error = OANDAService.OANDAError.invalidURL
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.errorDescription!.isEmpty)
        XCTAssertTrue(error.errorDescription!.contains("URL"))
    }

    func testInvalidResponseErrorHasDescription() {
        let error = OANDAService.OANDAError.invalidResponse
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.errorDescription!.isEmpty)
        XCTAssertTrue(error.errorDescription!.contains("response"))
    }

    func testUnauthorizedErrorHasDescription() {
        let error = OANDAService.OANDAError.unauthorized
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.errorDescription!.isEmpty)
        XCTAssertTrue(error.errorDescription!.contains("API"))
    }

    func testHTTPErrorIncludesStatusCode() {
        let error = OANDAService.OANDAError.httpError(503)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("503"))
    }

    func testNoAccountErrorHasDescription() {
        let error = OANDAService.OANDAError.noAccount
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.errorDescription!.isEmpty)
        XCTAssertTrue(error.errorDescription!.contains("account"))
    }

    func testAllErrorCasesHaveUniqueDescriptions() {
        let errors: [OANDAService.OANDAError] = [
            .invalidURL, .invalidResponse, .unauthorized, .httpError(400), .noAccount
        ]
        let descriptions = errors.compactMap(\.errorDescription)
        XCTAssertEqual(descriptions.count, errors.count, "All errors should have descriptions")
        XCTAssertEqual(Set(descriptions).count, descriptions.count, "All descriptions should be unique")
    }

    // MARK: - OANDATransaction Codable

    func testTransactionDecodeFromJSON() throws {
        let json = """
        {
            "id": "12345",
            "type": "ORDER_FILL",
            "time": "2025-03-15T10:30:00.000000000Z",
            "instrument": "EUR_USD",
            "units": "100000",
            "price": "1.08542",
            "tradeOpened": {
                "tradeID": "12345"
            }
        }
        """.data(using: .utf8)!

        let tx = try JSONDecoder().decode(OANDAService.OANDATransaction.self, from: json)
        XCTAssertEqual(tx.id, "12345")
        XCTAssertEqual(tx.type, "ORDER_FILL")
        XCTAssertEqual(tx.time, "2025-03-15T10:30:00.000000000Z")
        XCTAssertEqual(tx.instrument, "EUR_USD")
        XCTAssertEqual(tx.units, "100000")
        XCTAssertEqual(tx.price, "1.08542")
        XCTAssertEqual(tx.tradeOpened?.tradeID, "12345")
        XCTAssertNil(tx.tradesClosed)
    }

    func testTransactionDecodeClosingFill() throws {
        let json = """
        {
            "id": "12350",
            "type": "ORDER_FILL",
            "time": "2025-03-15T14:00:00.000000000Z",
            "instrument": "EUR_USD",
            "units": "-100000",
            "price": "1.08650",
            "tradesClosed": [
                {
                    "tradeID": "12345",
                    "realizedPL": "108.00"
                }
            ]
        }
        """.data(using: .utf8)!

        let tx = try JSONDecoder().decode(OANDAService.OANDATransaction.self, from: json)
        XCTAssertEqual(tx.id, "12350")
        XCTAssertEqual(tx.units, "-100000")
        XCTAssertNil(tx.tradeOpened)
        XCTAssertEqual(tx.tradesClosed?.count, 1)
        XCTAssertEqual(tx.tradesClosed?.first?.tradeID, "12345")
        XCTAssertEqual(tx.tradesClosed?.first?.realizedPL, "108.00")
    }

    func testTransactionDecodeMinimalFields() throws {
        // All fields are optional except what's required by Codable
        let json = """
        {}
        """.data(using: .utf8)!

        let tx = try JSONDecoder().decode(OANDAService.OANDATransaction.self, from: json)
        XCTAssertNil(tx.id)
        XCTAssertNil(tx.type)
        XCTAssertNil(tx.time)
        XCTAssertNil(tx.instrument)
        XCTAssertNil(tx.units)
        XCTAssertNil(tx.price)
        XCTAssertNil(tx.tradeOpened)
        XCTAssertNil(tx.tradesClosed)
    }

    func testTransactionRoundTrip() throws {
        let original = OANDAService.OANDATransaction(
            id: "99",
            type: "ORDER_FILL",
            time: "2025-06-01T08:15:30.123456789Z",
            instrument: "GBP_JPY",
            units: "-50000",
            price: "192.345",
            tradeOpened: nil,
            tradesClosed: [
                OANDAService.TradeClosedRef(tradeID: "88", realizedPL: "-42.50")
            ]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(OANDAService.OANDATransaction.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.type, original.type)
        XCTAssertEqual(decoded.time, original.time)
        XCTAssertEqual(decoded.instrument, original.instrument)
        XCTAssertEqual(decoded.units, original.units)
        XCTAssertEqual(decoded.price, original.price)
        XCTAssertNil(decoded.tradeOpened)
        XCTAssertEqual(decoded.tradesClosed?.count, 1)
        XCTAssertEqual(decoded.tradesClosed?.first?.tradeID, "88")
        XCTAssertEqual(decoded.tradesClosed?.first?.realizedPL, "-42.50")
    }

    func testTransactionMultipleClosedRefs() throws {
        // Partial close scenario: one fill closes multiple open trades
        let json = """
        {
            "id": "200",
            "type": "ORDER_FILL",
            "time": "2025-04-10T12:00:00Z",
            "instrument": "AUD_USD",
            "units": "-200000",
            "price": "0.66200",
            "tradesClosed": [
                { "tradeID": "150", "realizedPL": "35.00" },
                { "tradeID": "160", "realizedPL": "22.50" }
            ]
        }
        """.data(using: .utf8)!

        let tx = try JSONDecoder().decode(OANDAService.OANDATransaction.self, from: json)
        XCTAssertEqual(tx.tradesClosed?.count, 2)
        XCTAssertEqual(tx.tradesClosed?[0].tradeID, "150")
        XCTAssertEqual(tx.tradesClosed?[1].tradeID, "160")
    }

    // MARK: - AccountSummary Codable

    func testAccountSummaryDecodeFromJSON() throws {
        let json = """
        {
            "id": "101-004-12345678-001",
            "currency": "USD",
            "balance": "10542.83"
        }
        """.data(using: .utf8)!

        let summary = try JSONDecoder().decode(OANDAService.AccountSummary.self, from: json)
        XCTAssertEqual(summary.id, "101-004-12345678-001")
        XCTAssertEqual(summary.currency, "USD")
        XCTAssertEqual(summary.balance, "10542.83")
    }

    func testAccountSummaryRoundTrip() throws {
        let original = OANDAService.AccountSummary(
            id: "001-002-33333333-444",
            currency: "EUR",
            balance: "25000.00"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(OANDAService.AccountSummary.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.currency, original.currency)
        XCTAssertEqual(decoded.balance, original.balance)
    }

    // MARK: - TradeRef Codable

    func testTradeRefDecodeAndEncode() throws {
        let json = """
        { "tradeID": "77777" }
        """.data(using: .utf8)!

        let ref = try JSONDecoder().decode(OANDAService.TradeRef.self, from: json)
        XCTAssertEqual(ref.tradeID, "77777")

        let encoded = try JSONEncoder().encode(ref)
        let roundTripped = try JSONDecoder().decode(OANDAService.TradeRef.self, from: encoded)
        XCTAssertEqual(roundTripped.tradeID, "77777")
    }

    // MARK: - TradeClosedRef Codable

    func testTradeClosedRefWithPL() throws {
        let json = """
        { "tradeID": "555", "realizedPL": "-75.25" }
        """.data(using: .utf8)!

        let ref = try JSONDecoder().decode(OANDAService.TradeClosedRef.self, from: json)
        XCTAssertEqual(ref.tradeID, "555")
        XCTAssertEqual(ref.realizedPL, "-75.25")
    }

    func testTradeClosedRefWithoutPL() throws {
        let json = """
        { "tradeID": "556" }
        """.data(using: .utf8)!

        let ref = try JSONDecoder().decode(OANDAService.TradeClosedRef.self, from: json)
        XCTAssertEqual(ref.tradeID, "556")
        XCTAssertNil(ref.realizedPL)
    }

    // MARK: - OANDAService Initialization

    func testServiceInitSetsProperties() {
        let service = OANDAService(apiToken: "test-token-123", accountID: "101-001-12345", isLive: false)
        XCTAssertEqual(service.apiToken, "test-token-123")
        XCTAssertEqual(service.accountID, "101-001-12345")
        XCTAssertFalse(service.isLive)
    }

    func testServiceInitLiveMode() {
        let service = OANDAService(apiToken: "live-token", accountID: "001-002-33333", isLive: true)
        XCTAssertTrue(service.isLive)
    }

    // MARK: - Token-safety checks

    func testOnlyHTTPSOandaHostsAreTrusted() {
        XCTAssertTrue(OANDAService.isTrustedOANDAURL("https://api-fxpractice.oanda.com/v3/accounts/1/transactions"))
        XCTAssertTrue(OANDAService.isTrustedOANDAURL("https://oanda.com/x"))
        XCTAssertFalse(OANDAService.isTrustedOANDAURL("https://evil-oanda.com/x"))
        XCTAssertFalse(OANDAService.isTrustedOANDAURL("https://eviloanda.com/x"))
        XCTAssertFalse(OANDAService.isTrustedOANDAURL("https://oanda.com.evil.net/x"))
        XCTAssertFalse(OANDAService.isTrustedOANDAURL("http://api-fxpractice.oanda.com/x"))
        XCTAssertFalse(OANDAService.isTrustedOANDAURL("not a url"))
    }

    func testAccountIDValidation() {
        XCTAssertTrue(OANDAService.isValidAccountID("101-004-1234567-001"))
        XCTAssertFalse(OANDAService.isValidAccountID(""))
        XCTAssertFalse(OANDAService.isValidAccountID("../../v3/users"))
        XCTAssertFalse(OANDAService.isValidAccountID("1?x=y"))
        XCTAssertFalse(OANDAService.isValidAccountID("1/summary#"))
    }
}
