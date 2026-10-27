import Foundation
import os

/// Parses StrategyAnalytics CSV output into Trade objects
///
/// SA CSV format: comma-delimited, ANSI encoding, CRLF line endings.
/// Multi-section file — we only parse Section 3 (Trade Detail, 32 columns).
struct CSVParser: Sendable {
    private static let logger = Logger(subsystem: "com.dojix", category: "CSVParser")

    /// Maximum file size accepted for import (50 MB)
    private static let maxFileSize: UInt64 = 50 * 1024 * 1024

    enum ParseError: LocalizedError {
        case fileNotFound(String)
        case encodingError
        case noTradeSection
        case fileTooLarge(String)
        case invalidColumnCount(expected: Int, got: Int, line: Int)
        case invalidField(field: String, value: String, line: Int)

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let path): "File not found: \(path)"
            case .encodingError: "Could not read file — unsupported encoding"
            case .noTradeSection: "No trade detail section found in CSV"
            case .fileTooLarge(let size): "File is too large (\(size)). Maximum size is 50 MB."
            case .invalidColumnCount(let exp, let got, let line):
                "Expected \(exp) columns but got \(got) at line \(line)"
            case .invalidField(let field, let value, let line):
                "Invalid value '\(value)' for field '\(field)' at line \(line)"
            }
        }
    }

    /// Expected trade detail header
    private static let tradeHeader = "Ticket,Symbol,Direction,Lots,OpenTime,CloseTime,DurationMin,OpenPrice,ClosePrice,SL,TP,NetProfit,MAE_Pips,MFE_Pips,RMultiple,Session,DayOfWeek,Hour,RangeSize,SweepDepth,UsedFVG,VolRegime,HitBreakeven,ScaledIn,Magic,Comment,TimeToMFE_Min,SLDist_Pips,Slippage_Pips,PostClose15m,PostClose30m,BiasAtEntry"

    private static let expectedColumnCount = 32

    // MARK: - Public API

    /// Parse an SA CSV file at the given path. Returns parsed trades.
    static func parse(fileAt path: String) throws -> [Trade] {
        guard FileManager.default.fileExists(atPath: path) else {
            throw ParseError.fileNotFound(path)
        }

        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? UInt64, size > maxFileSize {
            let mb = String(format: "%.0f MB", Double(size) / 1_048_576)
            throw ParseError.fileTooLarge(mb)
        }

        // Try ANSI (UTF-8 compatible) first, then Windows-1252, then UTF-16LE
        let content: String
        if let str = try? String(contentsOfFile: path, encoding: .utf8) {
            content = str
        } else if let str = try? String(contentsOfFile: path, encoding: .windowsCP1252) {
            content = str
        } else if let data = FileManager.default.contents(atPath: path),
                  let str = String(data: data, encoding: .utf16LittleEndian) {
            content = str
        } else {
            throw ParseError.encodingError
        }

        // Split into lines, normalize CRLF
        let lines = content.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        return try parseTradeSection(from: lines)
    }

    // MARK: - Section Parsing

    /// Find and parse the Trade Detail section (Section 3)
    private static func parseTradeSection(from lines: [String]) throws -> [Trade] {
        // Find the trade header line
        guard let headerIndex = lines.firstIndex(where: { $0.hasPrefix("Ticket,Symbol,Direction") }) else {
            throw ParseError.noTradeSection
        }

        let now = Date()
        var trades: [Trade] = []

        // Parse data lines after the header until we hit an empty line or new section
        for i in (headerIndex + 1)..<lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.isEmpty { break }
            // Stop if we hit a new section header (non-numeric first field)
            if let firstChar = line.first, !firstChar.isNumber { break }

            do {
                let trade = try parseTradeLine(line, lineNumber: i + 1, importedAt: now)
                trades.append(trade)
            } catch {
                logger.warning("Skipping line \(i + 1): \(error.localizedDescription)")
                continue
            }
        }

        logger.info("Parsed \(trades.count) trades from CSV")
        return trades
    }

    /// Parse a single CSV data line into a Trade
    private static func parseTradeLine(_ line: String, lineNumber: Int, importedAt: Date) throws -> Trade {
        let fields = parseCSVLine(line)

        // Allow 26-32 columns for backwards compatibility
        guard fields.count >= 26 else {
            throw ParseError.invalidColumnCount(expected: expectedColumnCount, got: fields.count, line: lineNumber)
        }

        // Pad missing fields with defaults for older CSV formats
        var f = fields
        while f.count < expectedColumnCount {
            f.append(f.count == 31 ? "NEUTRAL" : "0")
        }

        guard let ticket = Int64(f[0]) else {
            throw ParseError.invalidField(field: "Ticket", value: f[0], line: lineNumber)
        }
        guard let direction = TradeDirection(rawValue: f[2].uppercased()) else {
            throw ParseError.invalidField(field: "Direction", value: f[2], line: lineNumber)
        }
        guard let openTime = Date.fromSADateTime(f[4]) else {
            throw ParseError.invalidField(field: "OpenTime", value: f[4], line: lineNumber)
        }
        guard let closeTime = Date.fromSADateTime(f[5]) else {
            throw ParseError.invalidField(field: "CloseTime", value: f[5], line: lineNumber)
        }

        let session = TradingSession(rawValue: f[15].uppercased()) ?? .late
        let volRegime = VolatilityRegime(rawValue: f[21].uppercased()) ?? .med
        let biasStr = f[31].trimmingCharacters(in: .whitespaces).uppercased()
        let bias = BiasAlignment(rawValue: biasStr) ?? .neutral

        return Trade(
            id: nil,
            ticket: ticket,
            symbol: f[1].uppercased(),
            direction: direction,
            lots: Double(f[3]) ?? 0,
            openTime: openTime,
            closeTime: closeTime,
            durationMin: Int(f[6]) ?? 0,
            openPrice: Decimal(string: f[7]) ?? 0,
            closePrice: Decimal(string: f[8]) ?? 0,
            sl: Decimal(string: f[9]) ?? 0,
            tp: Decimal(string: f[10]) ?? 0,
            netProfit: Decimal(string: f[11]) ?? 0,
            maePips: Double(f[12]) ?? 0,
            mfePips: Double(f[13]) ?? 0,
            rMultiple: Double(f[14]) ?? 0,
            session: session,
            dayOfWeek: f[16],
            hour: Int(f[17]) ?? 0,
            rangeSize: Double(f[18]) ?? 0,
            sweepDepth: Double(f[19]) ?? 0,
            usedFVG: f[20].uppercased() == "YES",
            volRegime: volRegime,
            hitBreakeven: f[22].uppercased() == "YES",
            scaledIn: f[23].uppercased() == "YES",
            magic: Int(f[24]) ?? 0,
            comment: f[25],
            timeToMFEMin: Int(f[26]) ?? 0,
            slDistPips: Double(f[27]) ?? 0,
            slippagePips: Double(f[28]) ?? 0,
            postClose15m: Double(f[29]) ?? 0,
            postClose30m: Double(f[30]) ?? 0,
            biasAtEntry: bias,
            importedAt: importedAt
        )
    }

    // MARK: - CSV Line Parser

    /// Parse a CSV line handling quoted fields with embedded commas
    private static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current.trimmingCharacters(in: .whitespaces))
        return fields
    }
}
