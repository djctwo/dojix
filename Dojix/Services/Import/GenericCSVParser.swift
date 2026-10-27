import CryptoKit
import Foundation
import os

/// Parses CSV trade exports from any platform by auto-detecting format or using column mapping
struct GenericCSVParser: Sendable {
    private static let logger = Logger(subsystem: "com.dojix", category: "GenericCSV")

    // MARK: - Platform Detection

    /// Known platform formats with their expected headers
    enum Platform: String, CaseIterable, Sendable {
        case strategyAnalytics = "StrategyAnalytics (MT5)"
        case mt4 = "MetaTrader 4"
        case cTrader = "cTrader"
        case tradingView = "TradingView"
        case oanda = "OANDA"
        case interactiveBrokers = "Interactive Brokers"
        case thinkorswim = "Thinkorswim"
        case ninjaTrader = "NinjaTrader"
        case generic = "Generic CSV"
    }

    /// Result of auto-detecting the CSV format
    struct DetectionResult: Sendable {
        let platform: Platform
        let headers: [String]
        let sampleRows: [[String]]
        let mapping: ColumnMapping?
    }

    /// Detect the platform format from a CSV file
    static func detect(fileAt path: String) throws -> DetectionResult {
        let content = try readFile(at: path)
        let lines = splitLines(content)
        guard let headerLine = lines.first, !headerLine.isEmpty else {
            throw GenericParseError.emptyFile
        }

        let headers = parseCSVLine(headerLine)
        let sampleRows = lines.dropFirst().prefix(5).map { parseCSVLine($0) }

        // Try to match against known formats
        let headerSet = Set(headers.map { $0.lowercased().trimmingCharacters(in: .whitespaces) })

        if headerSet.contains("ticket") && headerSet.contains("rmultiple") {
            return DetectionResult(platform: .strategyAnalytics, headers: headers, sampleRows: Array(sampleRows), mapping: nil)
        }

        if let mapping = detectPlatform(headers: headers, headerSet: headerSet) {
            return DetectionResult(platform: mapping.platform, headers: headers, sampleRows: Array(sampleRows), mapping: mapping)
        }

        // Unknown format — return headers for manual mapping
        return DetectionResult(platform: .generic, headers: headers, sampleRows: Array(sampleRows), mapping: nil)
    }

    // MARK: - Platform-Specific Detection

    private static func detectPlatform(headers: [String], headerSet: Set<String>) -> ColumnMapping? {
        // MT4 detailed report
        if headerSet.contains("ticket") && headerSet.contains("type") && headerSet.contains("item") && headerSet.contains("profit") {
            return mt4Mapping(headers: headers)
        }

        // cTrader
        if headerSet.contains("position id") && headerSet.contains("direction") && headerSet.contains("entry price") {
            return cTraderMapping(headers: headers)
        }
        if headerSet.contains("positionid") && headerSet.contains("direction") && headerSet.contains("entryprice") {
            return cTraderMapping(headers: headers)
        }

        // TradingView
        if headerSet.contains("trade #") && headerSet.contains("signal") && headerSet.contains("contracts") {
            return tradingViewMapping(headers: headers)
        }

        // OANDA
        if headerSet.contains("transaction id") && headerSet.contains("instrument") && headerSet.contains("units") {
            return oandaMapping(headers: headers)
        }

        // Interactive Brokers
        if headerSet.contains("tradeid") && headerSet.contains("symbol") && headerSet.contains("quantity") && headerSet.contains("t. price") {
            return ibMapping(headers: headers)
        }

        // Thinkorswim
        if headerSet.contains("exec time") && headerSet.contains("side") && headerSet.contains("qty") && headerSet.contains("symbol") {
            return tosMapping(headers: headers)
        }

        // NinjaTrader
        if headerSet.contains("trade #") && headerSet.contains("instrument") && headerSet.contains("market position") && headerSet.contains("entry price") {
            return ninjaTraderMapping(headers: headers)
        }

        return nil
    }

    // MARK: - Parse with Mapping

    /// Parse a CSV file using a column mapping (auto-detected or user-provided)
    static func parse(fileAt path: String, mapping: ColumnMapping) throws -> [Trade] {
        let content = try readFile(at: path)
        let lines = splitLines(content)
        guard lines.count > 1 else {
            throw GenericParseError.emptyFile
        }

        let headers = parseCSVLine(lines[0])
        let now = Date()
        let dates = DateParsers(primaryFormat: mapping.dateFormat)
        var trades: [Trade] = []
        var occurrences: [String: Int] = [:]

        for i in 1..<lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            let fields = parseCSVLine(line)
            guard fields.count >= 4 else { continue } // Need at least a few fields

            do {
                var trade = try mapToTrade(fields: fields, headers: headers, mapping: mapping, dates: dates, lineNumber: i + 1, importedAt: now)
                if trade.ticket == Self.noTicket {
                    // No broker ticket: derive a stable one from the trade's content, so
                    // importing the same file again is recognised as a duplicate.
                    let key = Self.contentKey(for: trade)
                    let seen = occurrences[key, default: 0]
                    occurrences[key] = seen + 1
                    trade.ticket = Self.contentTicket(key: key, occurrence: seen)
                }
                trades.append(trade)
            } catch {
                logger.warning("Skipping line \(i + 1): \(error.localizedDescription)")
            }
        }

        logger.info("Parsed \(trades.count) trades from \(mapping.platform.rawValue) CSV")
        return trades
    }

    // MARK: - Content-Derived Tickets

    /// Placeholder meaning "this row had no usable broker ticket"
    static let noTicket: Int64 = 0

    /// Content-derived tickets live in their own range, far above real broker tickets
    /// and the sample-trade range.
    private static let contentTicketBase: Int64 = 8_000_000_000_000_000_000

    /// Fields that identify a trade when the broker gives no ticket number
    static func contentKey(for trade: Trade) -> String {
        [
            trade.symbol, trade.direction.rawValue, String(format: "%.8f", trade.lots),
            String(trade.openTime.timeIntervalSince1970), String(trade.closeTime.timeIntervalSince1970),
            "\(trade.openPrice)", "\(trade.closePrice)", "\(trade.netProfit)"
        ].joined(separator: "|")
    }

    /// Stable ticket for the n-th row with this content (identical rows in one file stay separate trades)
    static func contentTicket(key: String, occurrence: Int) -> Int64 {
        let digest = SHA256.hash(data: Data("\(key)#\(occurrence)".utf8))
        let value = digest.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        return contentTicketBase + Int64(value % 1_000_000_000_000_000_000)
    }

    // MARK: - Field Mapping

    /// Maps CSV column indices to Trade fields
    struct ColumnMapping: Sendable {
        let platform: Platform
        let ticket: Int?
        let symbol: Int
        let direction: Int
        let lots: Int
        let openTime: Int
        let closeTime: Int?
        let openPrice: Int
        let closePrice: Int?
        let sl: Int?
        let tp: Int?
        let profit: Int
        let commission: Int?
        let swap: Int?
        let maePips: Int?
        let mfePips: Int?
        let pips: Int?
        let dateFormat: String

        /// Direction value mapping for this platform
        var buyValues: [String] { ["BUY", "LONG", "BOT", "B"] }
        var sellValues: [String] { ["SELL", "SHORT", "SLD", "S"] }
    }

    // MARK: - Trade Construction

    private static func mapToTrade(
        fields: [String],
        headers: [String],
        mapping: ColumnMapping,
        dates: DateParsers,
        lineNumber: Int,
        importedAt: Date
    ) throws -> Trade {
        // Symbol
        let symbol = cleanSymbol(fields[safe: mapping.symbol] ?? "")
        guard !symbol.isEmpty else {
            throw GenericParseError.missingField("symbol", lineNumber)
        }

        // Direction
        let dirStr = (fields[safe: mapping.direction] ?? "").uppercased().trimmingCharacters(in: .whitespaces)
        let direction: TradeDirection
        if mapping.buyValues.contains(dirStr) || dirStr.contains("BUY") || dirStr.contains("LONG") || dirStr.contains("BOT") {
            direction = .buy
        } else if mapping.sellValues.contains(dirStr) || dirStr.contains("SELL") || dirStr.contains("SHORT") || dirStr.contains("SLD") {
            direction = .sell
        } else {
            // Check for negative quantity (IB style: negative = sell)
            if let qty = Double(dirStr), qty < 0 {
                direction = .sell
            } else {
                throw GenericParseError.invalidDirection(dirStr, lineNumber)
            }
        }

        // Lots
        let lotsStr = fields[safe: mapping.lots] ?? "0"
        let lots = abs(Double(lotsStr.replacingOccurrences(of: ",", with: "")) ?? 0)

        // Times
        let openTimeStr = fields[safe: mapping.openTime] ?? ""
        guard let openTime = dates.parse(openTimeStr) else {
            throw GenericParseError.invalidDate(openTimeStr, lineNumber)
        }

        let closeTime: Date
        if let closeIdx = mapping.closeTime, let closeStr = fields[safe: closeIdx],
           let parsed = dates.parse(closeStr) {
            closeTime = parsed
        } else {
            closeTime = openTime
        }

        // Prices
        let openPrice = Decimal(string: fields[safe: mapping.openPrice]?.replacingOccurrences(of: ",", with: "") ?? "0") ?? 0
        let closePrice: Decimal
        if let cpIdx = mapping.closePrice, let cpStr = fields[safe: cpIdx] {
            closePrice = Decimal(string: cpStr.replacingOccurrences(of: ",", with: "")) ?? 0
        } else {
            closePrice = openPrice
        }

        // P&L
        let profitStr = fields[safe: mapping.profit]?.replacingOccurrences(of: ",", with: "") ?? "0"
        var profit = Decimal(string: profitStr) ?? 0

        // Add commission and swap if available
        if let commIdx = mapping.commission, let commStr = fields[safe: commIdx] {
            profit += Decimal(string: commStr.replacingOccurrences(of: ",", with: "")) ?? 0
        }
        if let swapIdx = mapping.swap, let swapStr = fields[safe: swapIdx] {
            profit += Decimal(string: swapStr.replacingOccurrences(of: ",", with: "")) ?? 0
        }

        // Optional fields
        let sl = mapping.sl.flatMap { fields[safe: $0] }.flatMap { Decimal(string: $0) } ?? 0
        let tp = mapping.tp.flatMap { fields[safe: $0] }.flatMap { Decimal(string: $0) } ?? 0
        let mae = mapping.maePips.flatMap { fields[safe: $0] }.flatMap { Double($0) } ?? 0
        let mfe = mapping.mfePips.flatMap { fields[safe: $0] }.flatMap { Double($0) } ?? 0

        // Ticket
        let ticket: Int64
        if let ticketIdx = mapping.ticket, let t = Int64(fields[safe: ticketIdx] ?? ""), t != noTicket {
            ticket = t
        } else {
            ticket = noTicket // replaced with a content-derived ticket by parse()
        }

        // Derived fields
        let duration = Int(saturating: closeTime.timeIntervalSince(openTime) / 60)
        let session = openTime.tradingSession
        let dayOfWeek = dates.dayName(openTime)
        let hour = openTime.utcHour

        // Calculate SL distance and R-multiple if we have SL
        let slDist: Double
        let rMult: Double
        if sl != 0 && openPrice != 0 {
            let slDistDecimal = abs(openPrice - sl)
            slDist = NSDecimalNumber(decimal: slDistDecimal).doubleValue * (symbol.contains("JPY") ? 100 : 10000)
            rMult = slDist > 0 ? NSDecimalNumber(decimal: profit).doubleValue / (slDist * lots * (symbol.contains("JPY") ? 100 : 10)) : 0
        } else {
            slDist = 0
            rMult = 0
        }

        return Trade(
            id: nil,
            ticket: ticket,
            symbol: symbol,
            direction: direction,
            lots: lots,
            openTime: openTime,
            closeTime: closeTime,
            durationMin: max(0, duration),
            openPrice: openPrice,
            closePrice: closePrice,
            sl: sl,
            tp: tp,
            netProfit: profit,
            maePips: mae,
            mfePips: mfe,
            rMultiple: rMult,
            session: session,
            dayOfWeek: dayOfWeek,
            hour: hour,
            rangeSize: 0,
            sweepDepth: 0,
            usedFVG: false,
            volRegime: .med,
            hitBreakeven: false,
            scaledIn: false,
            magic: 0,
            comment: "",
            timeToMFEMin: 0,
            slDistPips: slDist,
            slippagePips: 0,
            postClose15m: 0,
            postClose30m: 0,
            biasAtEntry: .neutral,
            importedAt: importedAt
        )
    }

    // MARK: - Platform Mappings

    private static func mt4Mapping(headers: [String]) -> ColumnMapping {
        let h = headers.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        return ColumnMapping(
            platform: .mt4,
            ticket: h.firstIndex(of: "ticket"),
            symbol: h.firstIndex(of: "item") ?? h.firstIndex(of: "symbol") ?? 0,
            direction: h.firstIndex(of: "type") ?? 0,
            lots: h.firstIndex(of: "size") ?? h.firstIndex(of: "volume") ?? 0,
            openTime: h.firstIndex(of: "open time") ?? h.firstIndex(of: "time") ?? 0,
            closeTime: h.firstIndex(of: "close time"),
            openPrice: h.firstIndex(of: "price") ?? h.firstIndex(of: "open price") ?? 0,
            closePrice: h.indices.last(where: { h[$0] == "price" && $0 != (h.firstIndex(of: "price") ?? -1) }) ?? h.firstIndex(of: "close price"),
            sl: h.firstIndex(of: "s/l") ?? h.firstIndex(of: "sl"),
            tp: h.firstIndex(of: "t/p") ?? h.firstIndex(of: "tp"),
            profit: h.firstIndex(of: "profit") ?? 0,
            commission: h.firstIndex(of: "commission"),
            swap: h.firstIndex(of: "swap") ?? h.firstIndex(of: "taxes"),
            maePips: nil,
            mfePips: nil,
            pips: h.firstIndex(of: "pips"),
            dateFormat: "yyyy.MM.dd HH:mm:ss"
        )
    }

    private static func cTraderMapping(headers: [String]) -> ColumnMapping {
        let h = headers.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        return ColumnMapping(
            platform: .cTrader,
            ticket: h.firstIndex(of: "position id") ?? h.firstIndex(of: "positionid"),
            symbol: h.firstIndex(of: "symbol") ?? 0,
            direction: h.firstIndex(of: "direction") ?? h.firstIndex(of: "type") ?? 0,
            lots: h.firstIndex(of: "volume") ?? h.firstIndex(of: "quantity") ?? 0,
            openTime: h.firstIndex(of: "entry time") ?? h.firstIndex(of: "opening time") ?? 0,
            closeTime: h.firstIndex(of: "close time") ?? h.firstIndex(of: "closing time"),
            openPrice: h.firstIndex(of: "entry price") ?? h.firstIndex(of: "opening price") ?? 0,
            closePrice: h.firstIndex(of: "close price") ?? h.firstIndex(of: "closing price"),
            sl: h.firstIndex(of: "stop loss") ?? h.firstIndex(of: "sl"),
            tp: h.firstIndex(of: "take profit") ?? h.firstIndex(of: "tp"),
            profit: h.firstIndex(of: "net profit") ?? h.firstIndex(of: "profit") ?? h.firstIndex(of: "net p&l") ?? 0,
            commission: h.firstIndex(of: "commission"),
            swap: h.firstIndex(of: "swap"),
            maePips: nil,
            mfePips: nil,
            pips: h.firstIndex(of: "pips"),
            dateFormat: "yyyy-MM-dd HH:mm:ss"
        )
    }

    private static func tradingViewMapping(headers: [String]) -> ColumnMapping {
        let h = headers.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        return ColumnMapping(
            platform: .tradingView,
            ticket: nil, // "Trade #" restarts at 1 in every export, so it isn't a unique ticket
            symbol: h.firstIndex(of: "symbol") ?? 0,
            direction: h.firstIndex(of: "type") ?? h.firstIndex(of: "side") ?? 0,
            lots: h.firstIndex(of: "contracts") ?? h.firstIndex(of: "qty") ?? 0,
            openTime: h.firstIndex(of: "date/time") ?? h.firstIndex(of: "date") ?? 0,
            closeTime: nil,
            openPrice: h.firstIndex(of: "price") ?? 0,
            closePrice: nil,
            sl: nil,
            tp: nil,
            profit: h.firstIndex(of: "profit") ?? h.firstIndex(of: "cumulative profit") ?? 0,
            commission: nil,
            swap: nil,
            maePips: h.firstIndex(of: "drawdown"),
            mfePips: h.firstIndex(of: "run-up"),
            pips: nil,
            dateFormat: "yyyy-MM-dd'T'HH:mm:ssZ"
        )
    }

    private static func oandaMapping(headers: [String]) -> ColumnMapping {
        let h = headers.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        return ColumnMapping(
            platform: .oanda,
            ticket: h.firstIndex(of: "transaction id") ?? h.firstIndex(of: "id"),
            symbol: h.firstIndex(of: "instrument") ?? 0,
            direction: h.firstIndex(of: "type") ?? h.firstIndex(of: "side") ?? 0,
            lots: h.firstIndex(of: "units") ?? 0,
            openTime: h.firstIndex(of: "open time") ?? h.firstIndex(of: "time") ?? 0,
            closeTime: h.firstIndex(of: "close time"),
            openPrice: h.firstIndex(of: "open price") ?? h.firstIndex(of: "price") ?? 0,
            closePrice: h.firstIndex(of: "close price"),
            sl: h.firstIndex(of: "s/l") ?? h.firstIndex(of: "stop loss"),
            tp: h.firstIndex(of: "t/p") ?? h.firstIndex(of: "take profit"),
            profit: h.firstIndex(of: "p/l") ?? h.firstIndex(of: "profit") ?? h.firstIndex(of: "realized p/l") ?? 0,
            commission: h.firstIndex(of: "commission"),
            swap: h.firstIndex(of: "financing") ?? h.firstIndex(of: "interest"),
            maePips: nil,
            mfePips: nil,
            pips: nil,
            dateFormat: "yyyy-MM-dd'T'HH:mm:ss"
        )
    }

    private static func ibMapping(headers: [String]) -> ColumnMapping {
        let h = headers.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        return ColumnMapping(
            platform: .interactiveBrokers,
            ticket: h.firstIndex(of: "tradeid"),
            symbol: h.firstIndex(of: "symbol") ?? 0,
            direction: h.firstIndex(of: "side") ?? h.firstIndex(of: "buy/sell") ?? 0,
            lots: h.firstIndex(of: "quantity") ?? h.firstIndex(of: "shares") ?? 0,
            openTime: h.firstIndex(of: "date/time") ?? h.firstIndex(of: "tradetime") ?? 0,
            closeTime: nil,
            openPrice: h.firstIndex(of: "t. price") ?? h.firstIndex(of: "tradeprice") ?? 0,
            closePrice: h.firstIndex(of: "c. price") ?? h.firstIndex(of: "closeprice"),
            sl: nil,
            tp: nil,
            profit: h.firstIndex(of: "realized p/l") ?? h.firstIndex(of: "mtm p/l") ?? h.firstIndex(of: "proceeds") ?? 0,
            commission: h.firstIndex(of: "comm/fee") ?? h.firstIndex(of: "commission"),
            swap: nil,
            maePips: nil,
            mfePips: nil,
            pips: nil,
            dateFormat: "yyyy-MM-dd, HH:mm:ss"
        )
    }

    private static func tosMapping(headers: [String]) -> ColumnMapping {
        let h = headers.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        return ColumnMapping(
            platform: .thinkorswim,
            ticket: nil,
            symbol: h.firstIndex(of: "symbol") ?? 0,
            direction: h.firstIndex(of: "side") ?? 0,
            lots: h.firstIndex(of: "qty") ?? h.firstIndex(of: "amount") ?? 0,
            openTime: h.firstIndex(of: "exec time") ?? h.firstIndex(of: "date") ?? 0,
            closeTime: nil,
            openPrice: h.firstIndex(of: "price") ?? h.firstIndex(of: "net price") ?? 0,
            closePrice: nil,
            sl: nil,
            tp: nil,
            profit: h.firstIndex(of: "p/l") ?? h.firstIndex(of: "net cash") ?? 0,
            commission: h.firstIndex(of: "commission") ?? h.firstIndex(of: "commissions"),
            swap: nil,
            maePips: nil,
            mfePips: nil,
            pips: nil,
            dateFormat: "MM/dd/yy HH:mm:ss"
        )
    }

    private static func ninjaTraderMapping(headers: [String]) -> ColumnMapping {
        let h = headers.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        return ColumnMapping(
            platform: .ninjaTrader,
            ticket: nil, // "Trade #" restarts at 1 in every export, so it isn't a unique ticket
            symbol: h.firstIndex(of: "instrument") ?? 0,
            direction: h.firstIndex(of: "market position") ?? 0,
            lots: h.firstIndex(of: "quantity") ?? h.firstIndex(of: "qty") ?? 0,
            openTime: h.firstIndex(of: "entry time") ?? 0,
            closeTime: h.firstIndex(of: "exit time"),
            openPrice: h.firstIndex(of: "entry price") ?? 0,
            closePrice: h.firstIndex(of: "exit price"),
            sl: nil,
            tp: nil,
            profit: h.firstIndex(of: "profit") ?? h.firstIndex(of: "net profit") ?? 0,
            commission: h.firstIndex(of: "commission"),
            swap: nil,
            maePips: h.firstIndex(of: "mae"),
            mfePips: h.firstIndex(of: "mfe"),
            pips: nil,
            dateFormat: "MM/dd/yyyy HH:mm:ss"
        )
    }

    // MARK: - Helpers

    private static let maxFileSize: UInt64 = 50 * 1024 * 1024

    private static func readFile(at path: String) throws -> String {
        guard FileManager.default.fileExists(atPath: path) else {
            throw GenericParseError.fileNotFound(path)
        }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? UInt64, size > maxFileSize {
            let mb = String(format: "%.0f MB", Double(size) / 1_048_576)
            throw GenericParseError.fileTooLarge(mb)
        }
        if let str = try? String(contentsOfFile: path, encoding: .utf8) {
            return str
        } else if let str = try? String(contentsOfFile: path, encoding: .windowsCP1252) {
            return str
        }
        throw GenericParseError.encodingError
    }

    private static func splitLines(_ content: String) -> [String] {
        content.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    static func parseCSVLine(_ line: String) -> [String] {
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

    private static func cleanSymbol(_ raw: String) -> String {
        raw.uppercased()
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Date formatters for one parse run. Building DateFormatters is expensive, so they are
    /// created once per file instead of once per row (a 50 MB file has ~400k rows).
    final class DateParsers {
        private let formatters: [DateFormatter]
        private let isoFractional = ISO8601DateFormatter()
        private let iso = ISO8601DateFormatter()
        private let dayFormatter = DateFormatter()

        init(primaryFormat: String) {
            let formats = [primaryFormat, "yyyy-MM-dd HH:mm:ss", "yyyy.MM.dd HH:mm:ss", "MM/dd/yyyy HH:mm:ss",
                           "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd, HH:mm:ss",
                           "MM/dd/yy HH:mm:ss", "dd/MM/yyyy HH:mm:ss", "yyyy-MM-dd"]
            var seen = Set<String>()
            formatters = formats.filter { seen.insert($0).inserted }.map { format in
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = format
                return formatter
            }
            isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            iso.formatOptions = [.withInternetDateTime]
            dayFormatter.locale = Locale(identifier: "en_US_POSIX")
            dayFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            dayFormatter.dateFormat = "EEE"
        }

        func parse(_ string: String) -> Date? {
            let trimmed = string.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed.count <= 64 else { return nil }
            for formatter in formatters {
                if let date = formatter.date(from: trimmed) { return date }
            }
            return isoFractional.date(from: trimmed) ?? iso.date(from: trimmed)
        }

        func dayName(_ date: Date) -> String {
            dayFormatter.string(from: date)
        }
    }

    // MARK: - Errors

    enum GenericParseError: LocalizedError {
        case fileNotFound(String)
        case encodingError
        case emptyFile
        case fileTooLarge(String)
        case missingField(String, Int)
        case invalidDirection(String, Int)
        case invalidDate(String, Int)

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let p): "File not found: \(p)"
            case .encodingError: "Could not read file — unsupported encoding"
            case .emptyFile: "CSV file is empty"
            case .fileTooLarge(let size): "File is too large (\(size)). Maximum size is 50 MB."
            case .missingField(let f, let l): "Missing required field '\(f)' at line \(l)"
            case .invalidDirection(let v, let l): "Cannot determine direction from '\(v)' at line \(l)"
            case .invalidDate(let v, let l): "Cannot parse date '\(v)' at line \(l)"
            }
        }
    }
}

// MARK: - Array Safe Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
