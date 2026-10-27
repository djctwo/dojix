import XCTest
@testable import Dojix

final class CSVParserTests: XCTestCase {

    // MARK: - CSV Line Parsing

    func testParseSimpleCSVLine() throws {
        let csv = """
        Ticket,Symbol,Direction,Lots,OpenTime,CloseTime,DurationMin,OpenPrice,ClosePrice,SL,TP,NetProfit,MAE_Pips,MFE_Pips,RMultiple,Session,DayOfWeek,Hour,RangeSize,SweepDepth,UsedFVG,VolRegime,HitBreakeven,ScaledIn,Magic,Comment,TimeToMFE_Min,SLDist_Pips,Slippage_Pips,PostClose15m,PostClose30m,BiasAtEntry
        100001,GBPUSD,BUY,0.10,2026.01.15 08:30:00,2026.01.15 09:45:00,75,1.25000,1.25250,1.24800,1.25500,25.00,8.5,30.2,1.25,LONDON,Wed,8,45.0,12.3,YES,MED,NO,NO,12345,test comment,35,20.0,0.5,15.0,22.0,WITH
        """

        let tempFile = NSTemporaryDirectory() + "test_parse_\(UUID().uuidString).csv"
        try csv.write(toFile: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        let trades = try CSVParser.parse(fileAt: tempFile)
        XCTAssertEqual(trades.count, 1)

        let trade = trades[0]
        XCTAssertEqual(trade.ticket, 100001)
        XCTAssertEqual(trade.symbol, "GBPUSD")
        XCTAssertEqual(trade.direction, .buy)
        XCTAssertEqual(trade.lots, 0.10, accuracy: 0.001)
        XCTAssertEqual(trade.durationMin, 75)
        XCTAssertEqual(trade.netProfit, Decimal(string: "25.00"))
        XCTAssertEqual(trade.maePips, 8.5, accuracy: 0.01)
        XCTAssertEqual(trade.mfePips, 30.2, accuracy: 0.01)
        XCTAssertEqual(trade.rMultiple, 1.25, accuracy: 0.01)
        XCTAssertEqual(trade.session, .london)
        XCTAssertEqual(trade.dayOfWeek, "Wed")
        XCTAssertEqual(trade.hour, 8)
        XCTAssertTrue(trade.usedFVG)
        XCTAssertEqual(trade.volRegime, .med)
        XCTAssertFalse(trade.hitBreakeven)
        XCTAssertFalse(trade.scaledIn)
        XCTAssertEqual(trade.magic, 12345)
        XCTAssertEqual(trade.comment, "test comment")
        XCTAssertEqual(trade.timeToMFEMin, 35)
        XCTAssertEqual(trade.slDistPips, 20.0, accuracy: 0.01)
        XCTAssertEqual(trade.slippagePips, 0.5, accuracy: 0.01)
        XCTAssertEqual(trade.postClose15m, 15.0, accuracy: 0.01)
        XCTAssertEqual(trade.postClose30m, 22.0, accuracy: 0.01)
        XCTAssertEqual(trade.biasAtEntry, .with)
    }

    func testParseMultipleTrades() throws {
        let csv = """
        Ticket,Symbol,Direction,Lots,OpenTime,CloseTime,DurationMin,OpenPrice,ClosePrice,SL,TP,NetProfit,MAE_Pips,MFE_Pips,RMultiple,Session,DayOfWeek,Hour,RangeSize,SweepDepth,UsedFVG,VolRegime,HitBreakeven,ScaledIn,Magic,Comment,TimeToMFE_Min,SLDist_Pips,Slippage_Pips,PostClose15m,PostClose30m,BiasAtEntry
        100001,GBPUSD,BUY,0.10,2026.01.15 08:30:00,2026.01.15 09:45:00,75,1.25000,1.25250,1.24800,1.25500,25.00,8.5,30.2,1.25,LONDON,Wed,8,45.0,12.3,YES,MED,NO,NO,12345,,35,20.0,0.5,15.0,22.0,WITH
        100002,EURUSD,SELL,0.20,2026.01.15 14:00:00,2026.01.15 15:30:00,90,1.08500,1.08200,1.08800,1.08000,60.00,5.0,35.0,2.00,NY_OVERLAP,Wed,14,38.0,8.0,NO,HIGH,YES,NO,12345,,40,30.0,1.0,20.0,28.0,AGAINST
        100003,USDJPY,BUY,0.05,2026.01.16 03:00:00,2026.01.16 04:15:00,75,150.500,150.200,150.800,150.000,-15.00,12.0,8.0,-0.50,ASIAN,Thu,3,55.0,15.0,YES,LOW,NO,NO,12345,,20,30.0,0.2,5.0,8.0,NEUTRAL
        """

        let tempFile = NSTemporaryDirectory() + "test_multi_\(UUID().uuidString).csv"
        try csv.write(toFile: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        let trades = try CSVParser.parse(fileAt: tempFile)
        XCTAssertEqual(trades.count, 3)
        XCTAssertEqual(trades[0].symbol, "GBPUSD")
        XCTAssertEqual(trades[1].symbol, "EURUSD")
        XCTAssertEqual(trades[2].symbol, "USDJPY")
        XCTAssertEqual(trades[1].direction, .sell)
        XCTAssertEqual(trades[2].biasAtEntry, .neutral)
    }

    func testParseFileNotFound() {
        XCTAssertThrowsError(try CSVParser.parse(fileAt: "/nonexistent/file.csv")) { error in
            guard let parseError = error as? CSVParser.ParseError else {
                XCTFail("Expected ParseError")
                return
            }
            if case .fileNotFound = parseError { } else {
                XCTFail("Expected fileNotFound error")
            }
        }
    }

    func testParseNoTradeSection() throws {
        let csv = "Some random content\nwith no trade headers\n"
        let tempFile = NSTemporaryDirectory() + "test_empty_\(UUID().uuidString).csv"
        try csv.write(toFile: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        XCTAssertThrowsError(try CSVParser.parse(fileAt: tempFile)) { error in
            guard let parseError = error as? CSVParser.ParseError else {
                XCTFail("Expected ParseError")
                return
            }
            if case .noTradeSection = parseError { } else {
                XCTFail("Expected noTradeSection error")
            }
        }
    }

    func testParseSellDirection() throws {
        let csv = """
        Ticket,Symbol,Direction,Lots,OpenTime,CloseTime,DurationMin,OpenPrice,ClosePrice,SL,TP,NetProfit,MAE_Pips,MFE_Pips,RMultiple,Session,DayOfWeek,Hour,RangeSize,SweepDepth,UsedFVG,VolRegime,HitBreakeven,ScaledIn,Magic,Comment,TimeToMFE_Min,SLDist_Pips,Slippage_Pips,PostClose15m,PostClose30m,BiasAtEntry
        200001,AUDUSD,SELL,0.50,2026.02.10 15:00:00,2026.02.10 16:30:00,90,0.65500,0.65200,0.65800,0.65000,150.00,3.0,32.0,3.00,NY_OVERLAP,Mon,15,42.0,10.0,NO,HIGH,NO,YES,99999,scaled entry,45,30.0,0.3,25.0,30.0,WITH
        """

        let tempFile = NSTemporaryDirectory() + "test_sell_\(UUID().uuidString).csv"
        try csv.write(toFile: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        let trades = try CSVParser.parse(fileAt: tempFile)
        XCTAssertEqual(trades.count, 1)
        XCTAssertEqual(trades[0].direction, .sell)
        XCTAssertTrue(trades[0].scaledIn)
        XCTAssertEqual(trades[0].volRegime, .high)
    }

    func testParseOlderCSVFormat26Columns() throws {
        // Older SA format with only 26 columns (no advanced metrics)
        let csv = """
        Ticket,Symbol,Direction,Lots,OpenTime,CloseTime,DurationMin,OpenPrice,ClosePrice,SL,TP,NetProfit,MAE_Pips,MFE_Pips,RMultiple,Session,DayOfWeek,Hour,RangeSize,SweepDepth,UsedFVG,VolRegime,HitBreakeven,ScaledIn,Magic,Comment
        300001,GBPJPY,BUY,0.10,2025.12.01 10:00:00,2025.12.01 11:00:00,60,185.500,186.000,185.000,186.500,50.00,10.0,55.0,1.00,LONDON,Mon,10,60.0,20.0,YES,MED,NO,NO,11111,old format
        """

        let tempFile = NSTemporaryDirectory() + "test_old_\(UUID().uuidString).csv"
        try csv.write(toFile: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        let trades = try CSVParser.parse(fileAt: tempFile)
        XCTAssertEqual(trades.count, 1)
        XCTAssertEqual(trades[0].ticket, 300001)
        // Padded fields should default
        XCTAssertEqual(trades[0].timeToMFEMin, 0)
        XCTAssertEqual(trades[0].slDistPips, 0)
        XCTAssertEqual(trades[0].biasAtEntry, .neutral)
    }

    func testParseWithMultiSectionCSV() throws {
        // SA CSVs have multiple sections — parser should find trade section
        let csv = """
        == Section 1: Summary ==
        Total Trades,12
        Win Rate,50.0%

        == Section 2: Settings ==
        EA,ExampleStrategy
        Timeframe,M15

        Ticket,Symbol,Direction,Lots,OpenTime,CloseTime,DurationMin,OpenPrice,ClosePrice,SL,TP,NetProfit,MAE_Pips,MFE_Pips,RMultiple,Session,DayOfWeek,Hour,RangeSize,SweepDepth,UsedFVG,VolRegime,HitBreakeven,ScaledIn,Magic,Comment,TimeToMFE_Min,SLDist_Pips,Slippage_Pips,PostClose15m,PostClose30m,BiasAtEntry
        400001,GBPUSD,BUY,0.10,2026.01.20 09:00:00,2026.01.20 10:00:00,60,1.26000,1.26100,1.25800,1.26300,10.00,5.0,12.0,0.50,LONDON,Mon,9,35.0,8.0,NO,MED,NO,NO,12345,,25,20.0,0.1,8.0,12.0,WITH

        == Section 4: More Data ==
        Something else
        """

        let tempFile = NSTemporaryDirectory() + "test_multi_section_\(UUID().uuidString).csv"
        try csv.write(toFile: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        let trades = try CSVParser.parse(fileAt: tempFile)
        XCTAssertEqual(trades.count, 1)
        XCTAssertEqual(trades[0].ticket, 400001)
    }
}
