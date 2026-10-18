import CoreGraphics
import Foundation
import ImageIO

/// Something went wrong reading a receipt.
public enum ReceiptOCRError: Error, Equatable {
    /// The file could not be decoded as an image.
    case unreadableImage(URL)
}

/// The entry point: image in, ``Receipt`` out.
///
/// ```swift
/// let receipt = try ReceiptOCR().scan(image: cgImage)
/// receipt.orderNumber?.value   // "10432"
/// receipt.items.first?.name    // "SOURDOUGH LOAF"
/// ```
///
/// Everything runs on-device. Nothing is sent anywhere, and there is no state
/// between calls, so it is safe to use from any thread.
public struct ReceiptOCR {

    /// Tuning knobs for the underlying Vision request.
    public struct Configuration {
        /// Restrict recognition to these BCP-47 language codes. `nil` lets the
        /// system decide, which is usually right for receipts.
        public var recognitionLanguages: [String]?
        /// Favour speed over accuracy — useful for live camera frames, where a
        /// second pass on a still image can follow.
        public var preferSpeedOverAccuracy: Bool
        /// Let Vision correct recognised words against a language model.
        public var usesLanguageCorrection: Bool
        /// Ignore text shorter than this fraction of the image height.
        public var minimumTextHeight: Float?

        public init(
            recognitionLanguages: [String]? = nil,
            preferSpeedOverAccuracy: Bool = false,
            usesLanguageCorrection: Bool = true,
            minimumTextHeight: Float? = nil
        ) {
            self.recognitionLanguages = recognitionLanguages
            self.preferSpeedOverAccuracy = preferSpeedOverAccuracy
            self.usesLanguageCorrection = usesLanguageCorrection
            self.minimumTextHeight = minimumTextHeight
        }
    }

    private let configuration: Configuration
    private let parser = ReceiptParser()

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Runs OCR over an image and parses the result.
    public func scan(image: CGImage) throws -> Receipt {
        var recognizer = VisionTextRecognizer()
        recognizer.recognitionLevel = configuration.preferSpeedOverAccuracy ? .fast : .accurate
        recognizer.usesLanguageCorrection = configuration.usesLanguageCorrection
        recognizer.recognitionLanguages = configuration.recognitionLanguages
        recognizer.minimumTextHeight = configuration.minimumTextHeight

        let words = try recognizer.recognize(in: image)
        let lines = LineAssembler.assemble(words).map(\.text)
        return parser.parse(lines: lines)
    }

    /// Loads an image from disk and parses it.
    public func scan(imageAt url: URL) throws -> Receipt {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ReceiptOCRError.unreadableImage(url)
        }
        return try scan(image: image)
    }

    /// Parses receipt text you already have, skipping OCR entirely.
    ///
    /// Useful if you use a different recognition engine, or when the caller has
    /// already extracted lines (including in tests).
    public func scan(lineText lines: [String]) -> Receipt {
        parser.parse(lines: lines)
    }
}

#if canImport(UIKit)
import UIKit

public extension ReceiptOCR {
    /// Runs OCR over a `UIImage`.
    func scan(image: UIImage) throws -> Receipt {
        guard let cgImage = image.cgImage else {
            throw ReceiptOCRError.unreadableImage(URL(fileURLWithPath: "UIImage"))
        }
        return try scan(image: cgImage)
    }

    /// Loads an image from `Data`, for example a photo picker result.
    func scan(imageData data: Data) throws -> Receipt {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ReceiptOCRError.unreadableImage(URL(fileURLWithPath: "imageData"))
        }
        return try scan(image: cgImage)
    }
}
#endif
