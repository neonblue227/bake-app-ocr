#if os(iOS)
import SwiftUI
import VisionKit

/// Continuous receipt scanning: point the camera at a receipt and text is
/// collected as you move down it.
///
/// Use this when a receipt is taller than the frame. It differs from
/// ``ReceiptCameraView`` in that nothing is captured up front — lines are
/// gathered live and only parsed when the user finishes, so panning slowly from
/// top to bottom collects the whole receipt.
///
/// The order of lines follows the order they were first recognised, which
/// matches reading order as long as the user starts at the top.
///
/// Requires `NSCameraUsageDescription` in your `Info.plist`. Live scanning needs
/// a device with an A12 chip or later and does not run in the Simulator.
public struct LiveReceiptScannerView: View {

    private let configuration: ReceiptOCR.Configuration
    private let onScan: (Receipt) -> Void

    @State private var accumulator = LiveTextAccumulator()

    public init(
        configuration: ReceiptOCR.Configuration = ReceiptOCR.Configuration(),
        onScan: @escaping (Receipt) -> Void
    ) {
        self.configuration = configuration
        self.onScan = onScan
    }

    public var body: some View {
        Group {
            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                scanner
            } else {
                unavailable
            }
        }
    }

    private var scanner: some View {
        ZStack {
            DataScannerRepresentable(languages: configuration.recognitionLanguages ?? []) { text in
                accumulator.add(text)
            }
            .ignoresSafeArea()

            VStack {
                Text("\(accumulator.count) lines read")
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.55), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(.top, 12)

                Spacer()

                HStack(spacing: 28) {
                    Button {
                        accumulator.reset()
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .labelStyle(.titleAndIcon)
                            .font(.subheadline)
                    }
                    .disabled(accumulator.isEmpty)

                    Button {
                        finish()
                    } label: {
                        Text("Done")
                            .font(.headline)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 12)
                            .background(.white, in: Capsule())
                            .foregroundStyle(.black)
                    }
                    .disabled(accumulator.isEmpty)
                }
                .padding(.bottom, 32)
            }
        }
    }

    private var unavailable: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.metering.unknown")
                .font(.largeTitle)
            Text("Live scanning is not available on this device. Use the still camera instead.")
                .multilineTextAlignment(.center)
                .font(.footnote)
        }
        .foregroundStyle(.white)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private func finish() {
        let receipt = ReceiptOCR(configuration: configuration).scan(lineText: accumulator.lines)
        onScan(receipt)
    }
}

/// Bridges `DataScannerViewController` into SwiftUI.
private struct DataScannerRepresentable: UIViewControllerRepresentable {
    let languages: [String]
    let onRecognized: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        // Like the still path, drop languages this device cannot scan. Asking
        // for a language this device does not have would otherwise leave an
        // empty set, so fall back to the unrestricted default.
        let supported = Set(DataScannerViewController.supportedTextRecognitionLanguages)
        let usable = languages.filter(supported.contains)
        let dataTypes: Set<DataScannerViewController.RecognizedDataType> =
            usable.isEmpty ? [.text()] : [.text(languages: usable)]

        let controller = DataScannerViewController(
            recognizedDataTypes: dataTypes,
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        guard !controller.isScanning else { return }
        try? controller.startScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onRecognized: onRecognized)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onRecognized: (String) -> Void

        init(onRecognized: @escaping (String) -> Void) {
            self.onRecognized = onRecognized
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            deliver(addedItems)
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didUpdate updatedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            deliver(updatedItems)
        }

        private func deliver(_ items: [RecognizedItem]) {
            for item in items {
                if case .text(let text) = item {
                    onRecognized(text.transcript)
                }
            }
        }
    }
}
#endif
