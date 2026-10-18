#if os(iOS)
import AVFoundation
import Combine
import CoreGraphics
import Foundation
import ImageIO

/// Something went wrong with the camera.
public enum ReceiptCameraError: Error, Equatable {
    /// The user declined camera access.
    case notAuthorized
    /// The session could not be configured.
    case configurationFailed(String)
    /// The capture itself failed.
    case captureFailed(String)
    /// The captured photo could not be decoded.
    case undecodablePhoto
    /// `capturePhoto()` was called before the session finished starting.
    case sessionNotRunning

    public var message: String {
        switch self {
        case .notAuthorized:
            return "Camera access was denied. Enable it in Settings to scan receipts."
        case .configurationFailed(let reason):
            return "The camera could not be started: \(reason)"
        case .captureFailed(let reason):
            return "The photo could not be captured: \(reason)"
        case .undecodablePhoto:
            return "The captured photo could not be read."
        case .sessionNotRunning:
            return "The camera is not running yet."
        }
    }
}

/// Owns the capture session behind ``ReceiptCameraView``.
///
/// Use this directly if you want to build your own camera UI and only borrow the
/// session and the capture call.
@MainActor
public final class ReceiptCameraSession: NSObject, ObservableObject {

    public enum State: Equatable {
        case idle
        case starting
        case running
        case denied
        case failed(String)
    }

    /// Attach this to an `AVCaptureVideoPreviewLayer` to show the live feed.
    public let session = AVCaptureSession()

    @Published public private(set) var state: State = .idle
    @Published public private(set) var isTorchOn = false
    @Published public private(set) var isCapturing = false

    private let photoOutput = AVCapturePhotoOutput()
    private var device: AVCaptureDevice?
    private var captureDelegate: PhotoCaptureDelegate?

    public override init() {
        super.init()
    }

    deinit {
        if session.isRunning { session.stopRunning() }
    }

    // MARK: - Lifecycle

    /// Requests camera access if needed, configures the session and starts the feed.
    public func start() async {
        if case .running = state { return }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else {
                state = .denied
                return
            }
        default:
            state = .denied
            return
        }

        state = .starting

        do {
            try configure()
        } catch {
            state = .failed((error as? ReceiptCameraError)?.message ?? error.localizedDescription)
            return
        }

        // `startRunning` blocks until the hardware is up, so keep it off the
        // main actor to avoid stalling the UI.
        let session = self.session
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
                continuation.resume()
            }
        }

        state = .running
    }

    public func stop() {
        guard session.isRunning else {
            state = .idle
            return
        }
        let session = self.session
        DispatchQueue.global(qos: .userInitiated).async {
            session.stopRunning()
        }
        state = .idle
    }

    private func configure() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        guard session.inputs.isEmpty else { return }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video)
        else {
            throw ReceiptCameraError.configurationFailed("no camera is available on this device")
        }
        self.device = device

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw ReceiptCameraError.configurationFailed("the camera input was rejected")
        }
        session.addInput(input)

        guard session.canAddOutput(photoOutput) else {
            throw ReceiptCameraError.configurationFailed("the photo output was rejected")
        }
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality

        // Receipts are normally held in the middle of the frame, so let the
        // camera keep that area continuously in focus.
        if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.continuousAutoFocus) {
            if (try? device.lockForConfiguration()) != nil {
                device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
                device.focusMode = .continuousAutoFocus
                device.unlockForConfiguration()
            }
        }
    }

    // MARK: - Capture

    /// Captures a still frame, ready for ``ReceiptOCR/scan(image:)``.
    ///
    /// A still is used rather than analysing live frames because a single sharp
    /// frame through Vision's accurate pass reads a dense receipt far better
    /// than a stream of tracking frames.
    public func capturePhoto() async throws -> CGImage {
        guard state == .running else { throw ReceiptCameraError.sessionNotRunning }

        isCapturing = true
        defer { isCapturing = false }

        return try await withCheckedThrowingContinuation { continuation in
            let delegate = PhotoCaptureDelegate { [weak self] result in
                continuation.resume(with: result)
                Task { @MainActor in self?.captureDelegate = nil }
            }
            // `AVCapturePhotoOutput` does not retain its delegate.
            captureDelegate = delegate

            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .quality
            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    /// Turns the torch on or off. Dim light is the most common cause of a
    /// receipt that will not read.
    public func setTorch(_ on: Bool) {
        guard let device, device.hasTorch, device.isTorchAvailable else { return }
        guard (try? device.lockForConfiguration()) != nil else { return }
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
        isTorchOn = on
    }

    /// Whether this device has a torch worth offering.
    public var hasTorch: Bool {
        device?.hasTorch ?? false
    }
}

/// Retained for the duration of a single capture.
private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Result<CGImage, Error>) -> Void

    init(completion: @escaping (Result<CGImage, Error>) -> Void) {
        self.completion = completion
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            completion(.failure(ReceiptCameraError.captureFailed(error.localizedDescription)))
            return
        }

        guard let data = photo.fileDataRepresentation(),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            completion(.failure(ReceiptCameraError.undecodablePhoto))
            return
        }

        completion(.success(image))
    }
}
#endif
