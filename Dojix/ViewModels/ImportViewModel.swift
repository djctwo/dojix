import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import os

/// ViewModel for the Import view — handles file selection, format detection, and import
@Observable
@MainActor
final class ImportViewModel {
    private let importer: SAImporter
    private let repository: TradeRepository
    private static let logger = Logger(subsystem: "com.dojix", category: "ImportVM")

    var isImporting: Bool { importer.isImporting }
    var importResults: [SAImporter.ImportResult] = []
    var isDragOver = false
    var showFileImporter = false
    var errorMessage: String?
    /// Called after a successful import (e.g., to navigate to Dashboard)
    var onImportSuccess: (() -> Void)?

    // MARK: - Format Detection State

    /// Pending file awaiting import (after detection)
    var pendingFile: PendingImport?
    /// Show column mapping sheet for unknown formats
    var showColumnMapping = false

    struct PendingImport: Sendable {
        let url: URL
        let detection: GenericCSVParser.DetectionResult
    }

    // MARK: - Import Confirmation

    /// Pre-import confirmation before bulk operations
    var showImportConfirmation = false
    var pendingConfirmation: ImportConfirmation?

    struct ImportConfirmation {
        let url: URL
        let formatName: String
        let estimatedTrades: Int
        let isSAFormat: Bool
        let detection: GenericCSVParser.DetectionResult?
    }

    init(importer: SAImporter, repository: TradeRepository) {
        self.importer = importer
        self.repository = repository
    }

    // MARK: - Actions

    /// Import from a file URL — detects format and shows confirmation first
    func importFile(at url: URL) async {

        let path = url.path
        let filename = url.lastPathComponent

        // Quick check: if filename matches SA pattern, use SA importer directly
        if filename.hasPrefix("StrategyAnalytics") || filename.hasPrefix("SA_Results") {
            let lineCount = await Self.estimateTradeCountInBackground(at: path)
            pendingConfirmation = ImportConfirmation(
                url: url, formatName: "StrategyAnalytics", estimatedTrades: lineCount,
                isSAFormat: true, detection: nil
            )
            showImportConfirmation = true
            return
        }

        // Auto-detect format
        do {
            let detection = try await Task.detached(priority: .userInitiated) { try GenericCSVParser.detect(fileAt: path) }.value

            switch detection.platform {
            case .strategyAnalytics:
                let lineCount = await Self.estimateTradeCountInBackground(at: path)
                pendingConfirmation = ImportConfirmation(
                    url: url, formatName: "StrategyAnalytics", estimatedTrades: lineCount,
                    isSAFormat: true, detection: detection
                )
                showImportConfirmation = true

            case .generic:
                // Unknown format — show column mapping UI (already a confirmation step)
                pendingFile = PendingImport(url: url, detection: detection)
                showColumnMapping = true

            default:
                // Known platform — show confirmation
                let lineCount = await Self.estimateTradeCountInBackground(at: path)
                pendingConfirmation = ImportConfirmation(
                    url: url, formatName: detection.platform.rawValue, estimatedTrades: lineCount,
                    isSAFormat: false, detection: detection
                )
                showImportConfirmation = true
            }
        } catch {
            let result = SAImporter.ImportResult(
                totalParsed: 0,
                newlyImported: 0,
                duplicatesSkipped: 0,
                errors: [error.localizedDescription],
                filename: filename
            )
            importResults.insert(result, at: 0)
            errorMessage = error.localizedDescription
        }
    }

    /// Confirm and execute pending import
    func confirmPendingImport() async {
        guard let confirmation = pendingConfirmation else { return }
        showImportConfirmation = false

        if confirmation.isSAFormat {
            let result = await importer.importFile(at: confirmation.url)
            importResults.insert(result, at: 0)
            if !result.errors.isEmpty {
                errorMessage = result.errors.joined(separator: "\n")
            }
            if result.newlyImported > 0 {
                onImportSuccess?()
            }
        } else if let detection = confirmation.detection, let mapping = detection.mapping {
            await importWithMapping(url: confirmation.url, mapping: mapping, platformName: confirmation.formatName)
        }

        pendingConfirmation = nil
    }

    /// Cancel pending import confirmation
    func cancelPendingImport() {
        showImportConfirmation = false
        pendingConfirmation = nil
    }

    /// Estimate trade count off the main thread so large files don't freeze the UI
    private static func estimateTradeCountInBackground(at path: String) async -> Int {
        await Task.detached(priority: .userInitiated) { estimateTradeCount(at: path) }.value
    }

    /// Estimate trade count from CSV line count (minus header)
    private nonisolated static func estimateTradeCount(at path: String) -> Int {
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) else {
            return 0
        }
        let lines = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return max(0, lines.count - 1) // subtract header row
    }

    /// Import using a column mapping (from auto-detection or manual mapping)
    func importWithMapping(url: URL, mapping: GenericCSVParser.ColumnMapping, platformName: String) async {
        let filename = url.lastPathComponent
        do {
            // Parse and write off the main thread so big files don't freeze the UI
            let path = url.path
            let repo = repository
            let (trades, insertedCount) = try await Task.detached(priority: .userInitiated) {
                let parsed = try GenericCSVParser.parse(fileAt: path, mapping: mapping)
                return (parsed, try repo.bulkInsert(parsed))
            }.value
            let result = SAImporter.ImportResult(
                totalParsed: trades.count,
                newlyImported: insertedCount,
                duplicatesSkipped: trades.count - insertedCount,
                errors: [],
                filename: filename
            )
            Self.logger.info("\(platformName) import: \(result.summary)")
            importResults.insert(result, at: 0)
            if insertedCount > 0 {
                onImportSuccess?()
            }
        } catch {
            let result = SAImporter.ImportResult(
                totalParsed: 0,
                newlyImported: 0,
                duplicatesSkipped: 0,
                errors: [error.localizedDescription],
                filename: filename
            )
            importResults.insert(result, at: 0)
            errorMessage = error.localizedDescription
        }
    }

    /// Confirm import with manual column mapping
    func confirmManualMapping(_ mapping: GenericCSVParser.ColumnMapping) async {
        guard let pending = pendingFile else { return }
        showColumnMapping = false
        await importWithMapping(url: pending.url, mapping: mapping, platformName: "Generic CSV")
        pendingFile = nil
    }

    /// Cancel pending manual mapping
    func cancelManualMapping() {
        showColumnMapping = false
        pendingFile = nil
    }

    /// Handle dropped file URLs
    func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                    guard let data = data as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil),
                          url.pathExtension.lowercased() == "csv" else { return }
                    Task { @MainActor in
                        await self.importFile(at: url)
                    }
                }
            }
        }
        return handled
    }

    /// Import trades directly from OANDA API
    var isOANDAImporting = false
    func importFromOANDA() async {
        guard let token = KeychainHelper.oandaAPIToken, !token.isEmpty,
              let accountID = KeychainHelper.oandaAccountID, !accountID.isEmpty else {
            errorMessage = "OANDA not configured — add your API token and account ID in Settings"
            return
        }

        isOANDAImporting = true
        defer { isOANDAImporting = false }

        let service = OANDAService(apiToken: token, accountID: accountID, isLive: KeychainHelper.oandaIsLive)
        do {
            let trades = try await service.fetchTrades()
            let insertedCount = try repository.bulkInsert(trades)
            let result = SAImporter.ImportResult(
                totalParsed: trades.count,
                newlyImported: insertedCount,
                duplicatesSkipped: trades.count - insertedCount,
                errors: [],
                filename: "OANDA API"
            )
            Self.logger.info("OANDA import: \(result.summary)")
            importResults.insert(result, at: 0)
            if insertedCount > 0 {
                onImportSuccess?()
            }
        } catch {
            let result = SAImporter.ImportResult(
                totalParsed: 0,
                newlyImported: 0,
                duplicatesSkipped: 0,
                errors: [error.localizedDescription],
                filename: "OANDA API"
            )
            importResults.insert(result, at: 0)
            errorMessage = error.localizedDescription
        }
    }

    /// Show folder picker and scan selected folder for CSVs
    func showFolderPicker() {
        let panel = NSOpenPanel()
        panel.title = "Choose Folder to Scan"
        panel.message = "Select a folder containing CSV trade exports"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        // Default to MT5 Common Files path if it exists
        let mt5Path = Configuration.mt5PrimaryFolder
        if FileManager.default.fileExists(atPath: mt5Path) {
            panel.directoryURL = URL(fileURLWithPath: mt5Path)
        }

        guard panel.runModal() == .OK, let folderURL = panel.url else { return }
        Task { await scanFolder(at: folderURL) }
    }

    /// Scan a folder for CSV files and import them
    func scanFolder(at folderURL: URL) async {

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            errorMessage = "Could not read folder: \(folderURL.lastPathComponent)"
            return
        }

        let csvURLs = contents.filter { $0.pathExtension.lowercased() == "csv" }

        guard !csvURLs.isEmpty else {
            errorMessage = "No CSV files found in \(folderURL.lastPathComponent)"
            return
        }

        for url in csvURLs {
            await importFile(at: url)
        }
    }

    /// Clear import history
    func clearHistory() {
        importResults.removeAll()
        errorMessage = nil
    }
}
