#if os(macOS)
import AppKit
import BakeAppOCR
import SwiftUI
import UniformTypeIdentifiers

/// Side-by-side inspector: drop in a receipt on the left, see exactly what the
/// parser made of it on the right.
///
/// The "Pasted text" mode skips OCR entirely, which is the fastest way to debug
/// a parsing rule without needing a photo.
struct ContentView: View {

    enum Mode: String, CaseIterable, Identifiable {
        case image
        case text

        var id: String { rawValue }

        var title: String {
            switch self {
            case .image: return "Image"
            case .text: return "Pasted text"
            }
        }
    }

    @State private var mode: Mode = .image
    @State private var imageURL: URL?
    @State private var previewImage: NSImage?
    @State private var pastedText = ""
    @State private var receipt: Receipt?
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var isImporting = false

    var body: some View {
        HSplitView {
            inputPane
                .frame(minWidth: 340, idealWidth: 430)
            resultPane
                .frame(minWidth: 460)
        }
    }

    // MARK: - Input

    private var inputPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Input", selection: $mode) {
                ForEach(Mode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch mode {
            case .image:
                imageInput
            case .text:
                textInput
            }

            HStack(spacing: 10) {
                Button("Read receipt", action: run)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canRun || isWorking)

                if isWorking {
                    ProgressView().controlSize(.small)
                }
                Spacer()
            }
        }
        .padding(16)
    }

    private var imageInput: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7]))
                .foregroundStyle(.quaternary)

            if let previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 34))
                        .foregroundStyle(.tertiary)
                    Text("Drop a receipt photo here")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomTrailing) {
            Button("Open Image…") { isImporting = true }
                .padding(10)
        }
        .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDrop)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                loadImage(at: url)
            }
        }
    }

    private var textInput: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("One OCR line per row. Skips OCR, so it tests the parser directly.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $pastedText)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 260)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.quaternary)
                )
        }
    }

    // MARK: - Results

    private var resultPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }

                if let receipt {
                    orderSection(receipt)
                    itemsSection(receipt)
                    totalsSection(receipt)
                    if !receipt.warnings.isEmpty {
                        warningsSection(receipt)
                    }
                    rawLinesSection(receipt)
                } else if errorMessage == nil {
                    Text("Read a receipt to see what the parser found.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toolbar {
            ToolbarItem {
                Button {
                    guard let receipt else { return }
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(
                        ReceiptSummary.text(for: receipt, includeRawLines: true),
                        forType: .string
                    )
                } label: {
                    Label("Copy summary", systemImage: "doc.on.doc")
                }
                .disabled(receipt == nil)
                .help("Copies the summary and the raw OCR lines, ready to paste into a bug report")
            }
        }
    }

    private func orderSection(_ receipt: Receipt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Order number").font(.headline)

            if let order = receipt.orderNumber {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(order.value)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .textSelection(.enabled)
                    confidenceBadge(order.confidence)
                    if let label = order.label {
                        Text(label)
                            .font(.caption)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text(order.sourceLine)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Text("not found").foregroundStyle(.secondary)
            }

            if receipt.orderNumberCandidates.count > 1 {
                DisclosureGroup("Other candidates (\(receipt.orderNumberCandidates.count - 1))") {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(receipt.orderNumberCandidates.dropFirst().enumerated()), id: \.offset) { _, candidate in
                            HStack(spacing: 8) {
                                Text(candidate.value).monospaced()
                                Text(candidate.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(ReceiptSummary.percent(candidate.confidence))
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.subheadline)
            }
        }
    }

    private func itemsSection(_ receipt: Receipt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Items (\(receipt.items.count))").font(.headline)

            if receipt.items.isEmpty {
                Text("none found").foregroundStyle(.secondary)
            }

            ForEach(Array(receipt.items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(ReceiptSummary.quantity(item))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 46, alignment: .trailing)

                    Text(item.name.isEmpty ? "(no description)" : item.name)
                        .foregroundStyle(item.name.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !item.isInternallyConsistent {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .help("quantity x unit price does not match the line total")
                    }

                    Text(ReceiptSummary.money(item.lineTotal))
                        .monospacedDigit()
                        .frame(width: 68, alignment: .trailing)

                    confidenceBadge(item.confidence)
                        .frame(width: 42, alignment: .trailing)
                }
                .font(.system(size: 13))
            }
        }
    }

    private func totalsSection(_ receipt: Receipt) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Totals").font(.headline)

            if let subtotal = receipt.subtotal { totalRow("Subtotal", subtotal) }
            if let tax = receipt.tax { totalRow("Tax", tax) }
            if let tip = receipt.tip { totalRow("Tip", tip) }
            totalRow("Total", receipt.total, emphasised: true)
        }
    }

    private func totalRow(_ title: String, _ value: Decimal?, emphasised: Bool = false) -> some View {
        HStack {
            Text(title).fontWeight(emphasised ? .semibold : .regular)
            Spacer()
            Text(ReceiptSummary.money(value))
                .monospacedDigit()
                .fontWeight(emphasised ? .semibold : .regular)
        }
        .frame(maxWidth: 320)
    }

    private func warningsSection(_ receipt: Receipt) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Warnings").font(.headline)
            ForEach(receipt.warnings.map(\.message), id: \.self) { message in
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func rawLinesSection(_ receipt: Receipt) -> some View {
        DisclosureGroup("Raw OCR lines (\(receipt.rawLines.count))") {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(receipt.rawLines.enumerated()), id: \.offset) { index, line in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .foregroundStyle(.tertiary)
                            .frame(width: 24, alignment: .trailing)
                        Text(line)
                            .textSelection(.enabled)
                    }
                    .font(.system(size: 11, design: .monospaced))
                }
            }
            .padding(.top, 6)
        }
        .font(.subheadline)
    }

    private func confidenceBadge(_ confidence: Double) -> some View {
        Text(ReceiptSummary.percent(confidence))
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(confidenceColor(confidence).opacity(0.18), in: Capsule())
            .foregroundStyle(confidenceColor(confidence))
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        switch confidence {
        case ..<0.5: return .red
        case ..<0.75: return .orange
        default: return .green
        }
    }

    // MARK: - Actions

    private var canRun: Bool {
        switch mode {
        case .image: return imageURL != nil
        case .text: return !pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func loadImage(at url: URL) {
        errorMessage = nil
        guard let image = NSImage(contentsOf: url) else {
            errorMessage = "That file could not be opened as an image."
            return
        }
        previewImage = image
        imageURL = url
        run()
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        _ = provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            var resolved: URL?
            if let url = item as? URL {
                resolved = url
            } else if let data = item as? Data {
                resolved = URL(dataRepresentation: data, relativeTo: nil)
            }
            guard let url = resolved else { return }
            Task { @MainActor in loadImage(at: url) }
        }
        return true
    }

    private func run() {
        let mode = self.mode
        let url = imageURL
        let text = pastedText

        errorMessage = nil
        isWorking = true

        Task {
            let outcome: Result<Receipt, Error>
            do {
                switch mode {
                case .image:
                    guard let url else {
                        await MainActor.run { isWorking = false }
                        return
                    }
                    outcome = .success(try ReceiptOCR().scan(imageAt: url))
                case .text:
                    let lines = text
                        .replacingOccurrences(of: "\r\n", with: "\n")
                        .split(separator: "\n", omittingEmptySubsequences: false)
                        .map(String.init)
                    outcome = .success(ReceiptOCR().scan(lineText: lines))
                }
            } catch {
                outcome = .failure(error)
            }

            await MainActor.run {
                isWorking = false
                switch outcome {
                case .success(let parsed):
                    receipt = parsed
                case .failure(let error):
                    receipt = nil
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
#endif
