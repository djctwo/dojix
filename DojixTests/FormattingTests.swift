import XCTest
@testable import Dojix

final class FormattingTests: XCTestCase {

    // MARK: - Double Formatting

    func testAsCurrencyPositive() {
        let result = 1234.56.asCurrency
        XCTAssertTrue(result.contains("1,234.56") || result.contains("1234.56"))
    }

    func testAsCurrencyNegative() {
        let result = (-500.0).asCurrency
        XCTAssertTrue(result.contains("500.00"))
    }

    func testAsCurrencyZero() {
        let result = 0.0.asCurrency
        XCTAssertTrue(result.contains("0.00"))
    }

    func testAsPips() {
        XCTAssertEqual(12.5.asPips, "12.5 pips")
        XCTAssertEqual(0.0.asPips, "0.0 pips")
        XCTAssertEqual((-3.2).asPips, "-3.2 pips")
    }

    func testAsPercent() {
        XCTAssertEqual(65.4.asPercent, "65.4%")
        XCTAssertEqual(100.0.asPercent, "100.0%")
        XCTAssertEqual(0.0.asPercent, "0.0%")
    }

    func testAsRMultiple() {
        XCTAssertEqual(1.5.asRMultiple, "1.50R")
        XCTAssertEqual((-0.3).asRMultiple, "-0.30R")
        XCTAssertEqual(0.0.asRMultiple, "0.00R")
    }

    func testAsProfitFactor() {
        XCTAssertEqual(1.85.asProfitFactor, "1.85")
        XCTAssertEqual(0.0.asProfitFactor, "0.00")
    }

    func testAsCompactCurrencyThousands() {
        let result = 15300.0.asCompactCurrency
        XCTAssertTrue(result.contains("15.3K"))
    }

    func testAsCompactCurrencyMillions() {
        let result = 1200000.0.asCompactCurrency
        XCTAssertTrue(result.contains("1.2M"))
    }

    func testAsCompactCurrencySmall() {
        let result = 500.0.asCompactCurrency
        XCTAssertTrue(result.contains("500.00"))
    }

    func testAsCompactCurrencyNegative() {
        let result = (-5000.0).asCompactCurrency
        XCTAssertTrue(result.contains("-"))
        XCTAssertTrue(result.contains("5.0K"))
    }

    // MARK: - Decimal Formatting

    func testDecimalAsCurrency() {
        let value: Decimal = 250.75
        let result = value.asCurrency
        XCTAssertTrue(result.contains("250.75"))
    }

    // MARK: - Date+Forex

    func testTradingSessionAsian() {
        // 3:00 UTC → Asian
        let cal = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 15
        components.hour = 3
        components.minute = 0
        components.timeZone = TimeZone(identifier: "UTC")
        let date = cal.date(from: components)!
        XCTAssertEqual(date.tradingSession, .asian)
    }

    func testTradingSessionLondon() {
        let cal = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 15
        components.hour = 9
        components.minute = 0
        components.timeZone = TimeZone(identifier: "UTC")
        let date = cal.date(from: components)!
        XCTAssertEqual(date.tradingSession, .london)
    }

    func testTradingSessionNYOverlap() {
        let cal = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 15
        components.hour = 14
        components.minute = 0
        components.timeZone = TimeZone(identifier: "UTC")
        let date = cal.date(from: components)!
        XCTAssertEqual(date.tradingSession, .nyOverlap)
    }

    func testTradingSessionNY() {
        let cal = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 15
        components.hour = 18
        components.minute = 0
        components.timeZone = TimeZone(identifier: "UTC")
        let date = cal.date(from: components)!
        XCTAssertEqual(date.tradingSession, .ny)
    }

    func testTradingSessionLate() {
        let cal = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 15
        components.hour = 22
        components.minute = 0
        components.timeZone = TimeZone(identifier: "UTC")
        let date = cal.date(from: components)!
        XCTAssertEqual(date.tradingSession, .late)
    }

    func testFromSADateTime() {
        let date = Date.fromSADateTime("2026.01.15 08:30:00")
        XCTAssertNotNil(date)

        let cal = Calendar(identifier: .gregorian)
        let components = cal.dateComponents(in: TimeZone(identifier: "UTC")!, from: date!)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 1)
        XCTAssertEqual(components.day, 15)
        XCTAssertEqual(components.hour, 8)
        XCTAssertEqual(components.minute, 30)
    }

    func testFromSADateTimeInvalid() {
        XCTAssertNil(Date.fromSADateTime("not a date"))
        XCTAssertNil(Date.fromSADateTime(""))
        XCTAssertNil(Date.fromSADateTime("Jan 15, 2026 8:30 AM"))
    }
}
