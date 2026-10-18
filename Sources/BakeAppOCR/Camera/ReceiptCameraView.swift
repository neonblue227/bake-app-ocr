#if os(iOS)
import AVFoundation
import SwiftUI
import UIKit

/// A live camera view that reads a receipt when the shutter is tapped.
///
/// The feed stays on screen so the user can frame the whole receipt, then a
/// single still is captured and run through the accurate OCR pass. That beats
/// reading live frames, because Vision does much better on one sharp image of a
/// dense receipt.
///
/// ```swift
/// .fullScreenCover(isPresented: $isScanning) {
///     ReceiptCameraView { receipt in
///         self.receipt = receipt
///         isScanning = false
///     }
/// }
/// ```
///
/// Requires `NSCameraUsageDescription` in your `Info.plist`.
public struct ReceiptCameraView: View {

    private let configuration: ReceiptOCR.Configuration
    private let onScan: (Receipt) -> Void

    @StateObject private var camera = ReceiptCameraSession()
    @State private var isWorking = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    public init(
        configuration: ReceiptOCR.Configuration = ReceiptOCR.Configuration(),
        onScan: @escaping (Receipt) -> Void
    ) {
        self.configuration = configuration
        self.onScan = onScan
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch camera.state {
            case .running:
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
            case .denied:
                message("Camera access is off. Enable it in Settings to scan receipts.")
            case .failed(let reason):
                message(reason)
            case .idle, .starting:
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.4)
            }

            VStack {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(10)
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                        .padding(.horizontal)
                }

                Spacer()

                if camera.state == .running {
                    Text("Fill the frame with the receipt, then tap to read")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.bottom, 12)
                }

                controls
            }
            .padding(.vertical, 24)
        }
        .task { await camera.start() }
        .onDisappear { camera.stop() }
    }

    private var controls: some View {
        HStack {
            if camera.hasTorch {
                circleButton(
                    systemImage: camera.isTorchOn ? "bolt.fill" : "bolt.slash",
                    isOn: camera.isTorchOn
                ) {
                    camera.setTorch(!camera.isTorchOn)
                }
            }

            Spacer()

            shutter

            Spacer()

            circleButton(systemImage: "xmark", isOn: false) {
                dismiss()
            }
        }
        .padding(.horizontal, 36)
    }

    private var shutter: some View {
        Button(action: capture) {
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 76, height: 76)
                Circle()
                    .fill(.white)
                    .frame(width: 62, height: 62)
                if isWorking {
                    ProgressView().tint(.black)
                }
            }
        }
        .disabled(camera.state != .running || isWorking)
        .opacity(camera.state == .running ? 1 : 0.4)
        .accessibilityLabel("Read receipt")
    }

    private func circleButton(
        systemImage: String,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(isOn ? .yellow : .white)
                .frame(width: 48, height: 48)
                .background(.black.opacity(0.4), in: Circle())
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(24)
    }

    private func capture() {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil

        Task {
            defer { isWorking = false }
            do {
                let image = try await camera.capturePhoto()
                let receipt = try ReceiptOCR(configuration: configuration).scan(image: image)
                onScan(receipt)
            } catch {
                errorMessage = (error as? ReceiptCameraError)?.message ?? error.localizedDescription
            }
        }
    }
}

/// Hosts an `AVCaptureVideoPreviewLayer` for SwiftUI.
private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            // Safe: `layerClass` guarantees the type.
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
#endif
