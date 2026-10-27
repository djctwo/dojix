import AppKit
import Foundation
import UniformTypeIdentifiers
import os

/// Exports trade data as CSV for spreadsheet analysis
final class CSVExporter: Sendable {
    private static let logger = Logger(subsystem: "com.dojix", category: "CSVExporter")

    /// Column headers for the export
    private static let headers = [
        "Ticket", "Symbol", "Direction", "Lots",
        "Open Time", "Close Time", "Duration (min)",
        "Open Price", "Close Price", "SL", "TP",
        "Net Profit", "MAE (pips)", "MFE (pips)", "R-Multiple",
        "Session", "Day", "Hour",
        "Range Size", "Sweep Depth", "Used FVG",
        "Vol Regime", "Hit BE", "Scaled In",
        "Bias", "Post Close 15m", "Post Close 30m"
    ]

    /// Export trades as CSV file
    func export(trades: [Trade], to url: URL) throws {
        let content = buildCSVContent(trades: trades)
        try OwnerOnlyFile.write(Data(content.utf8), to: url)
        Self.logger.info("CSV exported \(trades.count) trades to \(url.path)")
    }

    // MARK: - Private

    /// Build CSV string from trades (shared by both export methods)
    private func buildCSVContent(trades: [Trade]) -> String {
        var lines: [String] = []
        lines.append(Self.headers.joined(separator: ","))

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        for trade in trades {
            let row = [
                String(trade.ticket),
                trade.symbol,
                trade.direction.rawValue,
                String(format: "%.2f", trade.lots),
                dateFormatter.string(from: trade.openTime),
                dateFormatter.string(from: trade.closeTime),
                String(trade.durationMin),
                "\(trade.openPrice)",
                "\(trade.closePrice)",
                "\(trade.sl)",
                "\(trade.tp)",
                "\(trade.netProfit)",
                String(format: "%.1f", trade.maePips),
                String(format: "%.1f", trade.mfePips),
                String(format: "%.2f", trade.rMultiple),
                trade.session.rawValue,
                trade.dayOfWeek,
                String(trade.hour),
                String(format: "%.1f", trade.rangeSize),
                String(format: "%.1f", trade.sweepDepth),
                trade.usedFVG ? "YES" : "NO",
                trade.volRegime.rawValue,
                trade.hitBreakeven ? "YES" : "NO",
                trade.scaledIn ? "YES" : "NO",
                trade.biasAtEntry.rawValue,
                String(format: "%.1f", trade.postClose15m),
                String(format: "%.1f", trade.postClose30m)
            ].map { Self.sanitizeCSVField($0) }
            lines.append(row.joined(separator: ","))
        }

        return lines.joined(separator: "\n")
    }

    /// Sanitize a field for safe CSV output (prevents formula injection, handles commas/quotes)
    static func sanitizeCSVField(_ field: String) -> String {
        // Control characters (CR, LF, TAB, ...) have no place in an exported cell: a bare
        // CR or LF would start a new row whose first cell skipped the formula check below.
        let scalars = field.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        var value = String(String.UnicodeScalarView(scalars))
        // Prevent CSV formula injection — prefix dangerous characters with single quote.
        // Plain numbers (e.g. "-12.50") are left alone so spreadsheets still read them as numbers.
        if let first = value.first, "=+@-".contains(first), Double(value) == nil {
            value = "'" + value
        }
        // Quote fields containing commas, quotes or line breaks (CR as well as LF, should
        // a caller ever pass one through).
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            value = "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}

// MARK: - Save Panel

extension CSVExporter {
    /// Ask the user where to save a small CSV report, then write it.
    /// Returns the saved file URL, or nil if the user cancelled.
    @MainActor
    static func saveReport(lines: [String], suggestedName: String) throws -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = suggestedName
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        try OwnerOnlyFile.write(Data(lines.joined(separator: "\n").utf8), to: url)
        return url
    }
}
