import SwiftUI
import AppKit
import CryptoKit
import UniformTypeIdentifiers
import os

// MARK: - Screenshot Manager

/// Handles file operations for trade screenshot attachments.
///
/// Screenshots are stored encrypted with the database key (AES-256-GCM, "DJXS" header),
/// so they are as unreadable on disk as the journal. Files from older builds (plain
/// JPEG/PNG) still load and are encrypted in place by `encryptLegacyFiles()`.
/// Only names the app itself creates (`<UUID>.jpg`) are ever read, written or deleted.
final class ScreenshotManager: Sendable {
    static let shared = ScreenshotManager(keyProvider: { AppState.shared.database.currentKey })
    private static let logger = Logger(subsystem: "com.dojix", category: "ScreenshotManager")
    private static let sealedMagic = Data("DJXS".utf8)

    private let fixedBaseDir: URL?
    private let keyProvider: @Sendable () -> SymmetricKey?
    private let willSealLegacyFile: (@Sendable () -> Void)?
    private let willSaveImage: (@Sendable () -> Void)?
    /// Held while a screenshot file is read and (re)written with a key, so a key rotation
    /// re-sealing files and a save or legacy encryption with the key of the moment can't
    /// interleave (a file sealed with a key fetched before the rotation, written after
    /// the rotation passed it, would need the dropped old key).
    private let fileLock = NSLock()

    /// - Parameters:
    ///   - baseDir: folder for all screenshots (default: `<data dir>/Screenshots`).
    ///   - keyProvider: the database key, or nil while the journal is locked.
    ///   - willSealLegacyFile: test seam, called after a plain (older build) file was
    ///     read and before it is sealed.
    ///   - willSaveImage: test seam, called while a new screenshot is being saved (file
    ///     lock held, key taken) before it is written.
    init(baseDir: URL? = nil, keyProvider: @escaping @Sendable () -> SymmetricKey?,
         willSealLegacyFile: (@Sendable () -> Void)? = nil, willSaveImage: (@Sendable () -> Void)? = nil) {
        self.fixedBaseDir = baseDir
        self.keyProvider = keyProvider
        self.willSealLegacyFile = willSealLegacyFile
        self.willSaveImage = willSaveImage
    }

    /// Folder holding all screenshot attachments
    var baseDir: URL {
        fixedBaseDir ?? Configuration.dataDirectory.appendingPathComponent("Screenshots", isDirectory: true)
    }

    /// Get the screenshots directory for a trade
    func screenshotDir(for tradeId: Int64) -> URL {
        baseDir.appendingPathComponent("\(tradeId)", isDirectory: true)
    }

    /// Whether `filename` is a name this app creates: a UUID followed by ".jpg". Rejects
    /// ".", "..", hidden files, path separators and anything else.
    static func isValidFilename(_ filename: String) -> Bool {
        guard filename.count == 40, filename.hasSuffix(".jpg") else { return false }
        let stem = String(filename.dropLast(4))
        guard let uuid = UUID(uuidString: stem) else { return false }
        return uuid.uuidString.caseInsensitiveCompare(stem) == .orderedSame
    }

    /// Save an image to the trade's screenshot folder (encrypted), returns the filename
    func saveImage(_ image: NSImage, for tradeId: Int64) throws -> String {
        guard keyProvider() != nil else { throw ScreenshotError.locked }
        let dir = screenshotDir(for: tradeId)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
            throw ScreenshotError.encodingFailed
        }

        let filename = "\(UUID().uuidString).jpg"
        guard let url = imageURL(filename: filename, for: tradeId) else { throw ScreenshotError.invalidName }
        try fileLock.withLock {
            // The key of this moment (a rotation may have just switched it).
            guard let key = keyProvider() else { throw ScreenshotError.locked }
            willSaveImage?()
            try DatabaseEncryption.writeAtomically(Self.sealedMagic + DatabaseEncryption.seal(jpeg, key: key), to: url.path)
        }
        Self.logger.debug("Saved screenshot for trade \(tradeId)")
        return filename
    }

    /// Load an image by filename for a trade (nil if missing, invalid or locked)
    func loadImage(filename: String, for tradeId: Int64) -> NSImage? {
        guard let data = loadImageData(filename: filename, for: tradeId) else { return nil }
        return NSImage(data: data)
    }

    /// The decrypted image bytes (plain bytes for a file from an older build).
    func loadImageData(filename: String, for tradeId: Int64) -> Data? {
        guard let url = imageURL(filename: filename, for: tradeId),
              let data = try? Data(contentsOf: url) else { return nil }
        guard data.prefix(4) == Self.sealedMagic else { return data }
        guard let key = keyProvider() else { return nil }
        return try? DatabaseEncryption.open(data.dropFirst(4), key: key)
    }

    /// Delete a screenshot file
    func deleteImage(filename: String, for tradeId: Int64) throws {
        guard let url = imageURL(filename: filename, for: tradeId) else { throw ScreenshotError.invalidName }
        try FileManager.default.removeItem(at: url)
        Self.logger.debug("Deleted screenshot for trade \(tradeId)")
    }

    /// Full URL for a screenshot, or nil for any name the app would not have created.
    /// The resolved file must sit directly inside the trade's own folder.
    func imageURL(filename: String, for tradeId: Int64) -> URL? {
        guard Self.isValidFilename(filename) else {
            Self.logger.error("Rejected unsafe screenshot filename")
            return nil
        }
        let dir = screenshotDir(for: tradeId)
        let url = dir.appendingPathComponent(filename, isDirectory: false)
        // Lexical check (the whitelisted name has no "/" or ".." to resolve)
        guard url.lastPathComponent == filename, url.deletingLastPathComponent().path == dir.path else {
            return nil
        }
        return url
    }

    /// Key rotation: re-seal screenshots that open with `old` so they open with `new`
    /// (plain files from older builds are sealed with `new`). Returns what may still need
    /// `old`: files that could not be read, or opened with `old` but could not be
    /// re-written, and folders that could not be listed. The caller keeps `old` while
    /// this list is not empty.
    ///
    /// The list is taken under the file lock: a screenshot being saved with the key the
    /// journal had before the re-key is fully written before it, so it is in the list
    /// (any save that takes the lock later gets the new key).
    @discardableResult
    func reseal(from old: SymmetricKey, to new: SymmetricKey) -> [URL] {
        let (files, unlisted) = fileLock.withLock { screenshotFiles() }
        var pending = unlisted
        for file in files {
            fileLock.withLock {
                guard let data = try? Data(contentsOf: file) else {
                    Self.logger.error("Could not read a screenshot to re-seal it")
                    pending.append(file)
                    return
                }
                guard !data.isEmpty else { return }
                let plain: Data
                var needsOld = false
                if data.prefix(4) == Self.sealedMagic {
                    let body = data.dropFirst(4)
                    if (try? DatabaseEncryption.open(body, key: new)) != nil { return }
                    guard let opened = try? DatabaseEncryption.open(body, key: old) else { return }
                    plain = opened
                    needsOld = true
                } else {
                    plain = data   // an older build's plain file: needs no key
                }
                do {
                    let sealed = try DatabaseEncryption.seal(plain, key: new)
                    try DatabaseEncryption.writeAtomically(Self.sealedMagic + sealed, to: file.path)
                } catch {
                    Self.logger.error("Could not re-seal a screenshot: \(error.localizedDescription)")
                    if needsOld { pending.append(file) }
                }
            }
        }
        return pending
    }

    /// Every file with an app-created name, in every trade's folder, plus the folders
    /// that exist but could not be listed (their files are unknown).
    private func screenshotFiles() -> (files: [URL], unlisted: [URL]) {
        let fileManager = FileManager.default
        var isFolder: ObjCBool = false
        guard fileManager.fileExists(atPath: baseDir.path, isDirectory: &isFolder), isFolder.boolValue else {
            return ([], [])
        }
        guard let folders = try? fileManager.contentsOfDirectory(at: baseDir, includingPropertiesForKeys: nil) else {
            Self.logger.error("Could not list the screenshots folder")
            return ([], [baseDir])
        }
        var files: [URL] = []
        var unlisted: [URL] = []
        for folder in folders {
            guard fileManager.fileExists(atPath: folder.path, isDirectory: &isFolder), isFolder.boolValue else { continue }
            guard let names = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
                Self.logger.error("Could not list a trade's screenshot folder")
                unlisted.append(folder)
                continue
            }
            files += names.filter { Self.isValidFilename($0.lastPathComponent) }
        }
        return (files, unlisted)
    }

    /// Encrypt screenshots saved by older builds (plain image files) in place.
    /// Returns how many files were encrypted.
    @discardableResult
    func encryptLegacyFiles() -> Int {
        guard keyProvider() != nil else { return 0 }
        var count = 0
        for file in screenshotFiles().files {
            let sealedOne: Bool = fileLock.withLock {
                guard let data = try? Data(contentsOf: file), !data.isEmpty, data.prefix(4) != Self.sealedMagic else {
                    return false
                }
                willSealLegacyFile?()
                // The key of this moment, not one captured at the start: a key rotation
                // may have run meanwhile.
                guard let key = keyProvider(), let sealed = try? DatabaseEncryption.seal(data, key: key) else {
                    return false
                }
                return (try? DatabaseEncryption.writeAtomically(Self.sealedMagic + sealed, to: file.path)) != nil
            }
            if sealedOne { count += 1 }
        }
        if count > 0 { Self.logger.info("Encrypted \(count) screenshots saved by an older build") }
        return count
    }

    enum ScreenshotError: LocalizedError {
        case encodingFailed
        case invalidName
        case locked

        var errorDescription: String? {
            switch self {
            case .encodingFailed: "Failed to encode image as JPEG"
            case .invalidName: "That screenshot name is not one Dojix creates."
            case .locked: "Dojix is locked."
            }
        }
    }
}

// MARK: - Trade Screenshots View

/// Horizontal thumbnail strip for managing trade screenshot attachments
struct TradeScreenshots: View {
    let trade: Trade
    @Environment(\.appState) private var appState
    @State private var screenshots: [String] = []
    @State private var selectedImage: NSImage?
    @State private var showingImageViewer = false

    private let manager = ScreenshotManager.shared
    private static let maxScreenshots = 10
    private static let logger = Logger(subsystem: "com.dojix", category: "TradeScreenshots")

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Screenshots", systemImage: "photo.on.rectangle.angled")
                    .font(.smallText)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text("\(screenshots.count)/\(Self.maxScreenshots)")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(screenshots, id: \.self) { filename in
                        thumbnailView(for: filename)
                    }
                    if screenshots.count < Self.maxScreenshots {
                        addButton
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(12)
        .background(Color.bgCard, in: RoundedRectangle(cornerRadius: 8))
        .onDrop(of: [.image, .fileURL], isTargeted: nil, perform: handleDrop)
        .onAppear { screenshots = trade.screenshotList }
        .sheet(isPresented: $showingImageViewer) {
            if let image = selectedImage {
                ImageViewerSheet(image: image)
            }
        }
    }

    // MARK: - Thumbnail

    private func thumbnailView(for filename: String) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = manager.loadImage(filename: filename, for: trade.id ?? 0) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.gray.opacity(0.3)
                        .overlay { Image(systemName: "photo").foregroundStyle(Color.textTertiary) }
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.borderCard, lineWidth: 1)
            )
            .onTapGesture {
                selectedImage = manager.loadImage(filename: filename, for: trade.id ?? 0)
                showingImageViewer = selectedImage != nil
            }

            Button {
                deleteScreenshot(filename)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white, .red)
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
        }
    }

    // MARK: - Add Button

    private var addButton: some View {
        Button(action: openFilePicker) {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 80, height: 80)
                .overlay {
                    Image(systemName: "plus")
                        .font(.title2)
                        .foregroundStyle(Color.textSecondary)
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }

        let remaining = Self.maxScreenshots - screenshots.count
        for url in panel.urls.prefix(remaining) {
            guard let image = NSImage(contentsOf: url) else { continue }
            addImage(image)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard screenshots.count < Self.maxScreenshots else { return false }
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                guard let urlData = data as? Data,
                      let url = URL(dataRepresentation: urlData, relativeTo: nil),
                      UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true,
                      let image = NSImage(contentsOf: url) else { return }
                DispatchQueue.main.async { addImage(image) }
            }
        }
        return true
    }

    private func addImage(_ image: NSImage) {
        guard let tradeId = trade.id,
              screenshots.count < Self.maxScreenshots else { return }
        do {
            let filename = try manager.saveImage(image, for: tradeId)
            screenshots.append(filename)
            persistScreenshots(tradeId: tradeId)
        } catch {
            Self.logger.error("Failed to save screenshot: \(error.localizedDescription)")
        }
    }

    private func deleteScreenshot(_ filename: String) {
        guard let tradeId = trade.id else { return }
        try? manager.deleteImage(filename: filename, for: tradeId)
        screenshots.removeAll { $0 == filename }
        persistScreenshots(tradeId: tradeId)
    }

    private func persistScreenshots(tradeId: Int64) {
        let joined = screenshots.joined(separator: ",")
        try? appState.tradeRepository.updateScreenshots(tradeId: tradeId, screenshots: joined)
    }
}

// MARK: - Image Viewer Sheet

/// Full-size screenshot viewer presented as a sheet
struct ImageViewerSheet: View {
    let image: NSImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(12)

            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 800, maxHeight: 600)
                .padding()
        }
        .frame(minWidth: 400, minHeight: 300)
        .background(Color.bgCard)
    }
}
