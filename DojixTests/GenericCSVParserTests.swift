import XCTest
@testable import Dojix

final class GenericCSVParserTests: XCTestCase {

    // MARK: - Platform Detection

    func testDetectMT4Format() throws {
        let csv = "Ticket,Open Time,Close Time,Type,Size,Item,Price,S/L,T/P,Profit,Commission,Swap\n" +
                  "12345,2024.01.15 08:30:00,2024.01.15 09:45:00,BUY,0.10,GBPUSD,1.25000,1.24800,1.25500,25.00,-2.00,0.00\n"
        let path = writeTempCSV(csv, name: "mt4_detect")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let result = try GenericCSVParser.detect(fileAt: path)
        XCTAssertEqual(result.platform, .mt4)
        XCTAssertNotNil(result.mapping)
        XCTAssertEqual(result.mapping?.platform, .mt4)
    }

    func testDetectCTraderFormat() throws {
        let csv = "Position ID,Symbol,Direction,Volume,Entry Time,Close Time,Entry Price,Close Price,Stop Loss,Take Profit,Net Profit,Commission,Swap,Pips\n" +
                  "100001,EURUSD,BUY,10000,2024-01-15 08:30:00,2024-01-15 09:45:00,1.08500,1.08700,1.08200,1.09000,20.00,-1.50,0.00,20.0\n"
        let path = writeTempCSV(csv, name: "ctrader_detect")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let result = try GenericCSVParser.detect(fileAt: path)
        XCTAssertEqual(result.platform, .cTrader)
        XCTAssertNotNil(result.mapping)
    }

    func testDetectOANDAFormat() throws {
        let csv = "Transaction ID,Instrument,Type,Units,Open Time,Close Time,Open Price,Close Price,S/L,T/P,P/L,Financing\n" +
                  "5001,EUR_USD,BUY,10000,2024-01-15T08:30:00,2024-01-15T09:45:00,1.08500,1.08700,1.08200,1.09000,20.00,-0.50\n"
        let path = writeTempCSV(csv, name: "oanda_detect")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let result = try GenericCSVParser.detect(fileAt: path)
        XCTAssertEqual(result.platform, .oanda)
        XCTAssertNotNil(result.mapping)
    }

    func testDetectTradingViewFormat() throws {
        let csv = "Trade #,Date/Time,Type,Signal,Symbol,Contracts,Price,Profit,Cumulative Profit,Run-up,Drawdown\n" +
                  "1,2024-01-15T08:30:00Z,Entry Long,BUY,EURUSD,1,1.08500,0.00,0.00,0.0,0.0\n"
        let path = writeTempCSV(csv, name: "tv_detect")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let result = try GenericCSVParser.detect(fileAt: path)
        XCTAssertEqual(result.platform, .tradingView)
        XCTAssertNotNil(result.mapping)
    }

    func testDetectNinjaTraderFormat() throws {
        let csv = "Trade #,Instrument,Market Position,Quantity,Entry Time,Entry Price,Exit Time,Exit Price,Profit,Commission,MAE,MFE\n" +
                  "1,ES 03-24,Long,1,01/15/2024 08:30:00,4800.00,01/15/2024 09:45:00,4810.00,500.00,-4.00,100.00,600.00\n"
        let path = writeTempCSV(csv, name: "ninja_detect")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let result = try GenericCSVParser.detect(fileAt: path)
        XCTAssertEqual(result.platform, .ninjaTrader)
        XCTAssertNotNil(result.mapping)
    }

    func testDetectUnknownFormatReturnsGeneric() throws {
        let csv = "Column A,Column B,Column C,Column D\n" +
                  "foo,bar,baz,qux\n"
        let path = writeTempCSV(csv, name: "unknown_detect")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let result = try GenericCSVParser.detect(fileAt: path)
        XCTAssertEqual(result.platform, .generic)
        XCTAssertNil(result.mapping)
        XCTAssertEqual(result.headers, ["Column A", "Column B", "Column C", "Column D"])
    }

    func testDetectSAFormatWithRMultiple() throws {
        let csv = "Ticket,Symbol,Direction,Lots,OpenTime,CloseTime,DurationMin,OpenPrice,ClosePrice,SL,TP,NetProfit,MAE_Pips,MFE_Pips,RMultiple\n" +
                  "100001,GBPUSD,BUY,0.10,2026.01.15 08:30:00,2026.01.15 09:45:00,75,1.25000,1.25250,1.24800,1.25500,25.00,8.5,30.2,1.25\n"
        let path = writeTempCSV(csv, name: "sa_detect")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let result = try GenericCSVParser.detect(fileAt: path)
        XCTAssertEqual(result.platform, .strategyAnalytics)
        // SA format returns no mapping — it uses the dedicated CSVParser
        XCTAssertNil(result.mapping)
    }

    // MARK: - CSV Line Parsing

    func testParseCSVLineSimple() {
        let fields = GenericCSVParser.parseCSVLine("apple,banana,cherry")
        XCTAssertEqual(fields, ["apple", "banana", "cherry"])
    }

    func testParseCSVLineQuotedFieldsWithCommas() {
        let fields = GenericCSVParser.parseCSVLine("one,\"two, with comma\",three")
        XCTAssertEqual(fields.count, 3)
        XCTAssertEqual(fields[0], "one")
        XCTAssertEqual(fields[1], "two, with comma")
        XCTAssertEqual(fields[2], "three")
    }

    func testParseCSVLineEmptyFields() {
        let fields = GenericCSVParser.parseCSVLine("a,,c,")
        XCTAssertEqual(fields.count, 4)
        XCTAssertEqual(fields[0], "a")
        XCTAssertEqual(fields[1], "")
        XCTAssertEqual(fields[2], "c")
        XCTAssertEqual(fields[3], "")
    }

    // MARK: - Parse with Mapping (MT4 end-to-end)

    func testParseMT4CSVCreatesTradesCorrectly() throws {
        let csv = """
        Ticket,Open Time,Close Time,Type,Size,Item,Price,S/L,T/P,Close Price,Profit,Commission,Swap
        12345,2024.01.15 08:30:00,2024.01.15 09:45:00,BUY,0.10,GBPUSD,1.25000,1.24800,1.25500,1.25250,25.00,-2.00,-0.50
        12346,2024.01.15 14:00:00,2024.01.15 15:30:00,SELL,0.20,EURUSD,1.08500,1.08800,1.08000,1.08200,60.00,-4.00,0.00
        12347,2024.01.16 03:00:00,2024.01.16 04:15:00,BUY,0.05,USDJPY,150.500,150.000,151.000,150.200,-15.00,-1.00,0.00
        """

        let path = writeTempCSV(csv, name: "mt4_parse")
        defer { try? FileManager.default.removeItem(atPath: path) }

        // Detect first to get the mapping
        let detection = try GenericCSVParser.detect(fileAt: path)
        XCTAssertEqual(detection.platform, .mt4)

        let mapping = try XCTUnwrap(detection.mapping)
        let trades = try GenericCSVParser.parse(fileAt: path, mapping: mapping)

        XCTAssertEqual(trades.count, 3)

        // First trade
        let t1 = trades[0]
        XCTAssertEqual(t1.symbol, "GBPUSD")
        XCTAssertEqual(t1.direction, .buy)
        XCTAssertEqual(t1.lots, 0.10, accuracy: 0.001)
        // Profit = 25.00 + commission(-2.00) + swap(-0.50) = 22.50
        XCTAssertEqual(t1.netProfit, Decimal(string: "22.5"))
        XCTAssertEqual(t1.ticket, 12345)

        // Second trade
        let t2 = trades[1]
        XCTAssertEqual(t2.symbol, "EURUSD")
        XCTAssertEqual(t2.direction, .sell)
        XCTAssertEqual(t2.lots, 0.20, accuracy: 0.001)
        // Profit = 60.00 + (-4.00) + 0.00 = 56.00
        XCTAssertEqual(t2.netProfit, Decimal(string: "56"))

        // Third trade
        let t3 = trades[2]
        XCTAssertEqual(t3.symbol, "USDJPY")
        XCTAssertEqual(t3.direction, .buy)
        XCTAssertEqual(t3.lots, 0.05, accuracy: 0.001)
    }

    // MARK: - Date Parsing

    func testMultipleDateFormatsParseCorrectly() throws {
        // MT4 style: yyyy.MM.dd HH:mm:ss
        let mt4CSV = """
        Ticket,Open Time,Close Time,Type,Size,Item,Price,S/L,T/P,Profit,Commission
        1,2024.03.15 10:30:00,2024.03.15 11:00:00,BUY,0.10,EURUSD,1.08500,1.08200,1.09000,15.00,0.00
        """
        let mt4Path = writeTempCSV(mt4CSV, name: "mt4_dates")
        defer { try? FileManager.default.removeItem(atPath: mt4Path) }

        let mt4Detection = try GenericCSVParser.detect(fileAt: mt4Path)
        let mt4Mapping = try XCTUnwrap(mt4Detection.mapping)
        let mt4Trades = try GenericCSVParser.parse(fileAt: mt4Path, mapping: mt4Mapping)
        XCTAssertEqual(mt4Trades.count, 1)

        // cTrader style: yyyy-MM-dd HH:mm:ss
        let cTraderCSV = """
        Position ID,Symbol,Direction,Volume,Entry Time,Close Time,Entry Price,Close Price,Net Profit
        200,GBPUSD,BUY,10000,2024-03-15 10:30:00,2024-03-15 11:00:00,1.27500,1.27700,20.00
        """
        let cTraderPath = writeTempCSV(cTraderCSV, name: "ctrader_dates")
        defer { try? FileManager.default.removeItem(atPath: cTraderPath) }

        let cDetection = try GenericCSVParser.detect(fileAt: cTraderPath)
        let cMapping = try XCTUnwrap(cDetection.mapping)
        let cTrades = try GenericCSVParser.parse(fileAt: cTraderPath, mapping: cMapping)
        XCTAssertEqual(cTrades.count, 1)

        // NinjaTrader style: MM/dd/yyyy HH:mm:ss
        let ninjaCSV = """
        Trade #,Instrument,Market Position,Quantity,Entry Time,Entry Price,Exit Time,Exit Price,Profit
        1,ES 03-24,Long,1,01/15/2024 08:30:00,4800.00,01/15/2024 09:45:00,4810.00,500.00
        """
        let ninjaPath = writeTempCSV(ninjaCSV, name: "ninja_dates")
        defer { try? FileManager.default.removeItem(atPath: ninjaPath) }

        let nDetection = try GenericCSVParser.detect(fileAt: ninjaPath)
        let nMapping = try XCTUnwrap(nDetection.mapping)
        let nTrades = try GenericCSVParser.parse(fileAt: ninjaPath, mapping: nMapping)
        XCTAssertEqual(nTrades.count, 1)
    }

    // MARK: - Error Cases

    func testDetectEmptyFileThrows() throws {
        let path = writeTempCSV("", name: "empty_file")
        defer { try? FileManager.default.removeItem(atPath: path) }

        XCTAssertThrowsError(try GenericCSVParser.detect(fileAt: path)) { error in
            guard let parseError = error as? GenericCSVParser.GenericParseError else {
                XCTFail("Expected GenericParseError, got \(type(of: error))")
                return
            }
            if case .emptyFile = parseError { } else {
                XCTFail("Expected emptyFile error, got \(parseError)")
            }
        }
    }

    func testDetectFileNotFoundThrows() {
        XCTAssertThrowsError(try GenericCSVParser.detect(fileAt: "/nonexistent/path/trades.csv")) { error in
            guard let parseError = error as? GenericCSVParser.GenericParseError else {
                XCTFail("Expected GenericParseError, got \(type(of: error))")
                return
            }
            if case .fileNotFound = parseError { } else {
                XCTFail("Expected fileNotFound error, got \(parseError)")
            }
        }
    }

    func testParseHeaderOnlyFileThrows() throws {
        let csv = "Ticket,Open Time,Close Time,Type,Size,Item,Price,S/L,T/P,Profit\n"
        let path = writeTempCSV(csv, name: "header_only")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let detection = try GenericCSVParser.detect(fileAt: path)
        let mapping = try XCTUnwrap(detection.mapping)

        XCTAssertThrowsError(try GenericCSVParser.parse(fileAt: path, mapping: mapping)) { error in
            guard let parseError = error as? GenericCSVParser.GenericParseError else {
                XCTFail("Expected GenericParseError, got \(type(of: error))")
                return
            }
            if case .emptyFile = parseError { } else {
                XCTFail("Expected emptyFile error, got \(parseError)")
            }
        }
    }

    // MARK: - Detection Result Contents

    func testDetectionReturnsSampleRows() throws {
        let csv = """
        Ticket,Open Time,Type,Size,Item,Price,Profit
        1,2024.01.15 08:30:00,BUY,0.10,GBPUSD,1.25000,25.00
        2,2024.01.15 09:00:00,SELL,0.20,EURUSD,1.08500,30.00
        """
        let path = writeTempCSV(csv, name: "sample_rows")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let result = try GenericCSVParser.detect(fileAt: path)
        XCTAssertEqual(result.headers.count, 7)
        XCTAssertEqual(result.sampleRows.count, 2)
        XCTAssertEqual(result.sampleRows[0].first, "1")
        XCTAssertEqual(result.sampleRows[1].first, "2")
    }

    // MARK: - Helpers

    private func writeTempCSV(_ content: String, name: String) -> String {
        let path = NSTemporaryDirectory() + "test_\(name)_\(UUID().uuidString).csv"
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }
}
