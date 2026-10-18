import BakeAppOCR
import PhotosUI
import SwiftUI

/// Three ways into the package, so each can be tried on a device:
/// the still camera, the live scanner, and a photo from the library.
struct ContentView: View {

    private enum Scanner: String, Identifiable {
        case still
        case live

        var id: String { rawValue }
    }

    @State private var scanner: Scanner?
    @State private var photo: PhotosPickerItem?
    @State private var receipt: Receipt?
    @State private var isReading = false
    @State private var errorMessage: String?

    private let configuration = ReceiptOCR.Configuration()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        scanner = .still
                    } label: {
                        Label("Take a photo", systemImage: "camera")
                    }

                    Button {
                        scanner = .live
                    } label: {
                        Label("Live scan (long receipts)", systemImage: "text.viewfinder")
                    }

                    PhotosPicker(selection: $photo, matching: .images) {
                        Label("Choose from Photos", systemImage: "photo.on.rectangle")
                    }
                } footer: {
                    Text("Languages: \(languagesText). Thai needs iOS 17 or later.")
                }

                if isReading {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Reading receipt…")
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }

                if let receipt {
                    ReceiptSections(receipt: receipt)
                }
            }
            .navigationTitle("Receipt OCR")
            .toolbar {
                if receipt != nil {
                    Button("Clear") { receipt = nil }
                }
            }
        }
        .fullScreenCover(item: $scanner) { scanner in
            switch scanner {
            case .still:
                ReceiptCameraView(configuration: configuration) { result in
                    show(result)
                }
            case .live:
                LiveScannerScreen(configuration: configuration) { result in
                    show(result)
                }
            }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            read(item)
        }
    }

    private var languagesText: String {
        (configuration.recognitionLanguages ?? ["system default"]).joined(separator: ", ")
    }

    private func show(_ result: Receipt) {
        receipt = result
        errorMessage = nil
        scanner = nil
        // Handy when tuning the parser: copy this from the Xcode console.
        print("rawLines:", result.rawLines)
    }

    private func read(_ item: PhotosPickerItem) {
        isReading = true
        errorMessage = nil
        let configuration = configuration

        Task {
            defer {
                isReading = false
                photo = nil
            }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    errorMessage = "The photo could not be loaded."
                    return
                }
                // OCR is synchronous and slow; keep it off the main actor.
                let result = try await Task.detached {
                    try ReceiptOCR(configuration: configuration).scan(imageData: data)
                }.value
                show(result)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// `LiveReceiptScannerView` has no close button of its own.
private struct LiveScannerScreen: View {
    let configuration: ReceiptOCR.Configuration
    let onScan: (Receipt) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        LiveReceiptScannerView(configuration: configuration, onScan: onScan)
            .overlay(alignment: .topTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.4), in: Circle())
                }
                .padding()
            }
    }
}

/// Everything the parser returned, including the raw OCR lines.
private struct ReceiptSections: View {
    let receipt: Receipt

    var body: some View {
        Section("Fields") {
            row("Merchant", receipt.merchant)
            row("Date", receipt.date)
            row("Order number", receipt.orderNumber.map {
                "\($0.value) (\(Int(($0.confidence * 100).rounded()))%)"
            })
            row("Subtotal", receipt.subtotal.map(format))
            row("Tax", receipt.tax.map(format))
            row("Tip", receipt.tip.map(format))
            row("Total", receipt.total.map(format))
        }

        if !receipt.items.isEmpty {
            Section("Items (\(receipt.items.count))") {
                ForEach(Array(receipt.items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading) {
                            Text(item.name.isEmpty ? "—" : item.name)
                            if let quantity = item.quantity {
                                Text("Qty \(format(quantity))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(item.lineTotal.map(format) ?? "—")
                            .monospacedDigit()
                    }
                }
            }
        }

        if !receipt.warnings.isEmpty {
            Section("Warnings") {
                ForEach(Array(receipt.warnings.enumerated()), id: \.offset) { _, warning in
                    Text(warning.message)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }

        Section {
            ForEach(Array(receipt.rawLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
            }
        } header: {
            HStack {
                Text("Raw OCR lines (\(receipt.rawLines.count))")
                Spacer()
                Button("Copy") {
                    UIPasteboard.general.string = receipt.rawLines.joined(separator: "\n")
                }
                .font(.caption)
            }
        }
    }

    private func row(_ title: String, _ value: String?) -> some View {
        LabeledContent(title) {
            Text(value ?? "—")
                .foregroundStyle(value == nil ? .secondary : .primary)
                .textSelection(.enabled)
        }
    }

    private func format(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}
