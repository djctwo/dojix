import Foundation
import os

/// Orchestrates importing SA CSV files into the database
@Observable
final class SAImporter {
    private let repository: TradeRepository
    private static let logger = Logger(subsystem: "com.dojix", category: "SAImporter")

    var isImporting = false
    var lastImportResult: ImportResult?

    init(repository: TradeRepository) {
        self.repository = repository
    }

    struct ImportResult: Sendable {
        let totalParsed: Int
        let newlyImported: Int
        let duplicatesSkipped: Int
        let errors: [String]
        let filename: String

        var summary: String {
            if newlyImported == 0 && errors.isEmpty {
                return "No new trades found in \(filename)"
            }
            var parts = ["\(newlyImported) new trades imported"]
            if duplicatesSkipped > 0 {
                parts.append("\(duplicatesSkipped) duplicates skipped")
            }
            if !errors.isEmpty {
                parts.append("\(errors.count) errors")
            }
            return parts.joined(separator: ", ")
        }
    }

    // MARK: - Import

    /// Import trades from an SA CSV file at the given path
    @MainActor
    func importFile(at path: String) async -> ImportResult {
        isImporting = true
        defer { isImporting = false }

        let filename = (path as NSString).lastPathComponent

        do {
            // Parse and write off the main thread so big files don't freeze the UI
            let repo = repository
            let (trades, insertedCount) = try await Task.detached(priority: .userInitiated) {
                let parsed = try CSVParser.parse(fileAt: path)
                return (parsed, try repo.bulkInsert(parsed))
            }.value
            let result = ImportResult(
                totalParsed: trades.count,
                newlyImported: insertedCount,
                duplicatesSkipped: trades.count - insertedCount,
                errors: [],
                filename: filename
            )
            Self.logger.info("Import complete: \(result.summary)")
            lastImportResult = result
            return result

        } catch {
            let result = ImportResult(
                totalParsed: 0,
                newlyImported: 0,
                duplicatesSkipped: 0,
                errors: [error.localizedDescription],
                filename: filename
            )
            Self.logger.error("Import failed: \(error.localizedDescription)")
            lastImportResult = result
            return result
        }
    }

    /// Import from a file URL (drag-and-drop)
    @MainActor
    func importFile(at url: URL) async -> ImportResult {
        await importFile(at: url.path)
    }

    /// Scan the MT5 folder(s) for SA CSV files and import all
    @MainActor
    func importFromMT5CommonFiles() async -> [ImportResult] {
        var results: [ImportResult] = []
        for dir in Configuration.mt5WatchFolders where FileManager.default.fileExists(atPath: dir) {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
            for file in files.sorted() where file.hasPrefix(Configuration.saCSVPattern) && file.lowercased().hasSuffix(".csv") {
                let fullPath = (dir as NSString).appendingPathComponent(file)
                results.append(await importFile(at: fullPath))
            }
        }
        return results
    }
}
