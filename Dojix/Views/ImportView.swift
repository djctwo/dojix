import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @Bindable var viewModel: ImportViewModel
    @Environment(\.appState) private var appState

    var body: some View {
        VStack(spacing: 24) {
            dropZone
            supportedPlatforms
            importActions
            importHistory
            Spacer()
        }
        .padding(24)
        .navigationTitle("Import Trades")
        .fileImporter(
            isPresented: $viewModel.showFileImporter,
            allowedContentTypes: [.commaSeparatedText, UTType(filenameExtension: "csv")!],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                for url in urls {
                    Task { await viewModel.importFile(at: url) }
                }
            case .failure(let error):
                viewModel.errorMessage = error.friendlyMessage
            }
        }
        .sheet(isPresented: $viewModel.showColumnMapping) {
            if let pending = viewModel.pendingFile {
                ColumnMappingSheet(
                    headers: pending.detection.headers,
                    sampleRows: pending.detection.sampleRows,
                    onConfirm: { mapping in
                        Task { await viewModel.confirmManualMapping(mapping) }
                    },
                    onCancel: { viewModel.cancelManualMapping() }
                )
            }
        }
        .alert("Import Trades?", isPresented: $viewModel.showImportConfirmation) {
            Button("Import") {
                Task { await viewModel.confirmPendingImport() }
            }
            .keyboardShortcut(.return)
            Button("Cancel", role: .cancel) {
                viewModel.cancelPendingImport()
            }
        } message: {
            if let confirmation = viewModel.pendingConfirmation {
                Text("Found ~\(confirmation.estimatedTrades) trades in \(confirmation.formatName) format.\n\nDuplicates will be skipped automatically.")
            }
        }
    }

    // MARK: - Drop Zone

    private var dropZone: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 40))
                .foregroundStyle(viewModel.isDragOver ? Color.accent : .secondary)

            Text("Drop CSV Trade Export Here")
                .font(.title3)
                .fontWeight(.medium)

            Text("Auto-detects MT5, MT4, cTrader, OANDA, and more")
                .font(.smallText)
                .foregroundStyle(Color.textSecondary)

            if viewModel.isImporting {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    viewModel.isDragOver ? Color.accent : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                )
        )
        .background(
            viewModel.isDragOver
            ? Color.accent.opacity(0.05)
            : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: $viewModel.isDragOver) { providers in
            viewModel.handleDrop(providers: providers)
        }
    }

    // MARK: - Supported Platforms

    private var supportedPlatforms: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Supported Platforms")
                    .font(.smallText)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text("Just drop your CSV — Dojix detects the format automatically")
                    .font(.smallText)
                    .foregroundStyle(Color.textTertiary)
            }

            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 130), spacing: 8)
            ], spacing: 6) {
                ForEach(platformItems, id: \.name) { item in
                    HStack(spacing: 6) {
                        Image(systemName: item.icon)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.accent)
                            .frame(width: 14)
                        Text(item.name)
                            .font(.smallText)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.bgCard.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
               .overlay(
                   RoundedRectangle(cornerRadius: 12)
                       .stroke(Color.borderCard, lineWidth: 1)
               )
                }
            }
        }
    }

    private var platformItems: [(name: String, icon: String)] {
        [
            ("StrategyAnalytics", "chart.bar.doc.horizontal"),
            ("MetaTrader 4", "chart.line.uptrend.xyaxis"),
            ("cTrader", "arrow.left.arrow.right"),
            ("TradingView", "tv"),
            ("OANDA", "dollarsign.circle"),
            ("Interactive Brokers", "building.columns"),
            ("Thinkorswim", "waveform.path.ecg"),
            ("NinjaTrader", "flame"),
            ("Generic CSV", "doc.text"),
        ]
    }

    // MARK: - Import Actions

    private var importActions: some View {
        HStack(spacing: 16) {
            Button {
                viewModel.showFileImporter = true
            } label: {
                Label("Choose File", systemImage: "folder")
            }
            .controlSize(.large)

            Button {
                viewModel.showFolderPicker()
            } label: {
                Label("Scan Folder for CSVs", systemImage: "folder.badge.gearshape")
            }
            .controlSize(.large)
            .help("Choose a folder to scan for CSV trade exports")

            if KeychainHelper.oandaAPIToken != nil {
                Button {
                    Task { await viewModel.importFromOANDA() }
                } label: {
                    Label(
                        viewModel.isOANDAImporting ? "Importing..." : "Import from OANDA",
                        systemImage: "arrow.down.circle"
                    )
                }
                .controlSize(.large)
                .disabled(viewModel.isOANDAImporting)
                .help("Fetch trade history from your OANDA account")
            }
        }
    }

    // MARK: - Import History

    @ViewBuilder
    private var importHistory: some View {
        if !viewModel.importResults.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Import History")
                        .font(.headline)
                    Spacer()
                    Button("Clear") { viewModel.clearHistory() }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.textSecondary)
                        .font(.smallText)
                }

                ForEach(Array(viewModel.importResults.enumerated()), id: \.offset) { _, result in
                    HStack {
                        Image(systemName: result.errors.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(result.errors.isEmpty ? Color.semanticGreen : Color.semanticRed)
                            .font(.smallText)
                        Text(result.filename)
                            .font(.smallText)
                            .fontWeight(.medium)
                        Spacer()
                        Text(result.summary)
                            .font(.smallText)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(8)
                    .background(Color.bgContent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
               .overlay(
                   RoundedRectangle(cornerRadius: 12)
                       .stroke(Color.borderCard, lineWidth: 1)
               )
                }
            }
        }

        if let error = viewModel.errorMessage {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(error)
                    .font(.smallText)
                    .foregroundStyle(Color.semanticRed)
                Spacer()
                Button("Dismiss") { viewModel.errorMessage = nil }
                    .font(.smallText)
            }
            .padding(10)
            .background(Color.semanticRed.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
       .overlay(
           RoundedRectangle(cornerRadius: 12)
               .stroke(Color.borderCard, lineWidth: 1)
       )
        }
    }
}

// MARK: - Column Mapping Sheet

/// Manual column mapping UI for unknown CSV formats
struct ColumnMappingSheet: View {
    let headers: [String]
    let sampleRows: [[String]]
    let onConfirm: (GenericCSVParser.ColumnMapping) -> Void
    let onCancel: () -> Void

    @State private var symbolCol = 0
    @State private var directionCol = 0
    @State private var lotsCol = 0
    @State private var openTimeCol = 0
    @State private var closeTimeCol: Int? = nil
    @State private var openPriceCol = 0
    @State private var closePriceCol: Int? = nil
    @State private var profitCol = 0
    @State private var slCol: Int? = nil
    @State private var tpCol: Int? = nil
    @State private var ticketCol: Int? = nil
    @State private var commissionCol: Int? = nil
    @State private var swapCol: Int? = nil
    @State private var dateFormat = "yyyy-MM-dd HH:mm:ss"

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Map CSV Columns")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            // Preview
            csvPreview
                .padding()

            Divider()

            // Mapping form
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Required Fields")
                        .font(.smallText)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.textSecondary)

                    mappingRow("Symbol", selection: $symbolCol)
                    mappingRow("Direction (Buy/Sell)", selection: $directionCol)
                    mappingRow("Lot Size", selection: $lotsCol)
                    mappingRow("Open Time", selection: $openTimeCol)
                    mappingRow("Open Price", selection: $openPriceCol)
                    mappingRow("Profit/P&L", selection: $profitCol)

                    Divider()

                    Text("Optional Fields")
                        .font(.smallText)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.textSecondary)

                    optionalMappingRow("Close Time", selection: $closeTimeCol)
                    optionalMappingRow("Close Price", selection: $closePriceCol)
                    optionalMappingRow("Stop Loss", selection: $slCol)
                    optionalMappingRow("Take Profit", selection: $tpCol)
                    optionalMappingRow("Ticket/ID", selection: $ticketCol)
                    optionalMappingRow("Commission", selection: $commissionCol)
                    optionalMappingRow("Swap/Financing", selection: $swapCol)

                    Divider()

                    HStack {
                        Text("Date Format")
                            .font(.smallText)
                            .frame(width: 140, alignment: .leading)
                        TextField("yyyy-MM-dd HH:mm:ss", text: $dateFormat)
                            .textFieldStyle(.roundedBorder)
                            .font(.monoSubtitle)
                    }
                }
                .padding()
            }

            Divider()

            // Actions
            HStack {
                Spacer()
                Button("Import") {
                    let mapping = GenericCSVParser.ColumnMapping(
                        platform: .generic,
                        ticket: ticketCol,
                        symbol: symbolCol,
                        direction: directionCol,
                        lots: lotsCol,
                        openTime: openTimeCol,
                        closeTime: closeTimeCol,
                        openPrice: openPriceCol,
                        closePrice: closePriceCol,
                        sl: slCol,
                        tp: tpCol,
                        profit: profitCol,
                        commission: commissionCol,
                        swap: swapCol,
                        maePips: nil,
                        mfePips: nil,
                        pips: nil,
                        dateFormat: dateFormat
                    )
                    onConfirm(mapping)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding()
        }
        .frame(width: 600, height: 650)
        .onAppear { autoAssignColumns() }
    }

    // MARK: - CSV Preview

    private var csvPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("File Preview")
                .font(.smallText)
                .fontWeight(.semibold)
                .foregroundStyle(Color.textSecondary)

            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 2) {
                    // Header row
                    HStack(spacing: 0) {
                        ForEach(Array(headers.enumerated()), id: \.offset) { i, header in
                            Text(header)
                                .font(.monoSubtitle)
                                .fontWeight(.bold)
                                .frame(width: 100, alignment: .leading)
                                .padding(2)
                                .background(i % 2 == 0 ? Color.clear : Color.secondary.opacity(0.05))
                        }
                    }
                    Divider()
                    // Sample rows
                    ForEach(Array(sampleRows.prefix(3).enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 0) {
                            ForEach(Array(row.enumerated()), id: \.offset) { i, field in
                                Text(field)
                                    .font(.monoSubtitle)
                                    .frame(width: 100, alignment: .leading)
                                    .padding(2)
                                    .lineLimit(1)
                                    .background(i % 2 == 0 ? Color.clear : Color.secondary.opacity(0.05))
                            }
                        }
                    }
                }
            }
            .padding(8)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
       .overlay(
           RoundedRectangle(cornerRadius: 12)
               .stroke(Color.borderCard, lineWidth: 1)
       )
        }
    }

    // MARK: - Mapping Rows

    private func mappingRow(_ label: String, selection: Binding<Int>) -> some View {
        HStack {
            Text(label)
                .font(.smallText)
                .frame(width: 140, alignment: .leading)
            Picker("", selection: selection) {
                ForEach(Array(headers.enumerated()), id: \.offset) { i, header in
                    Text("\(i): \(header)").tag(i)
                }
            }
            .labelsHidden()
            .frame(width: 200)
        }
    }

    private func optionalMappingRow(_ label: String, selection: Binding<Int?>) -> some View {
        HStack {
            Text(label)
                .font(.smallText)
                .frame(width: 140, alignment: .leading)
            Picker("", selection: selection) {
                Text("— None —").tag(nil as Int?)
                ForEach(Array(headers.enumerated()), id: \.offset) { i, header in
                    Text("\(i): \(header)").tag(i as Int?)
                }
            }
            .labelsHidden()
            .frame(width: 200)
        }
    }

    // MARK: - Auto-assign

    /// Best-effort auto-assign columns based on header names
    private func autoAssignColumns() {
        let h = headers.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }

        if let i = h.firstIndex(where: { $0.contains("symbol") || $0.contains("pair") || $0.contains("instrument") || $0.contains("item") }) {
            symbolCol = i
        }
        if let i = h.firstIndex(where: { $0.contains("direction") || $0.contains("type") || $0.contains("side") || $0.contains("buy") }) {
            directionCol = i
        }
        if let i = h.firstIndex(where: { $0.contains("lot") || $0.contains("volume") || $0.contains("size") || $0.contains("qty") || $0.contains("quantity") || $0.contains("units") || $0.contains("contracts") }) {
            lotsCol = i
        }
        if let i = h.firstIndex(where: { $0.contains("open time") || $0.contains("entry time") || $0.contains("date") || $0.contains("time") }) {
            openTimeCol = i
        }
        if let i = h.firstIndex(where: { $0.contains("open price") || $0.contains("entry price") || $0.contains("price") }) {
            openPriceCol = i
        }
        if let i = h.firstIndex(where: { $0.contains("profit") || $0.contains("p/l") || $0.contains("p&l") || $0.contains("net") }) {
            profitCol = i
        }
        closeTimeCol = h.firstIndex(where: { $0.contains("close time") || $0.contains("exit time") || $0.contains("closing time") })
        closePriceCol = h.firstIndex(where: { $0.contains("close price") || $0.contains("exit price") || $0.contains("closing price") })
        slCol = h.firstIndex(where: { $0.contains("stop loss") || $0 == "sl" || $0 == "s/l" })
        tpCol = h.firstIndex(where: { $0.contains("take profit") || $0 == "tp" || $0 == "t/p" })
        ticketCol = h.firstIndex(where: { $0.contains("ticket") || $0.contains("trade #") || $0.contains("id") || $0.contains("positionid") })
        commissionCol = h.firstIndex(where: { $0.contains("commission") || $0.contains("comm") })
        swapCol = h.firstIndex(where: { $0.contains("swap") || $0.contains("financing") || $0.contains("interest") })
    }
}
