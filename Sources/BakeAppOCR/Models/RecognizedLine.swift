import CoreGraphics
import Foundation

/// A single word returned by the OCR engine, with its bounding box.
///
/// Coordinates follow Vision's convention: the origin is the *bottom left* of
/// the image and both axes are normalised to `0...1`.
public struct RecognizedWord: Equatable {
    public let text: String
    public let boundingBox: CGRect
    public let confidence: Float

    public init(text: String, boundingBox: CGRect, confidence: Float) {
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
    }
}

/// A visual line: words that share a baseline, ordered left to right.
///
/// Vision hands back words in no particular order, so grouping them into lines
/// is the step every parser downstream depends on.
public struct RecognizedLine: Equatable {
    public let words: [RecognizedWord]

    public init(words: [RecognizedWord]) {
        self.words = words
    }

    /// The line's text, words joined by a single space.
    public var text: String {
        words
            .map(\.text)
            .joined(separator: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Union of every word box on the line.
    public var boundingBox: CGRect {
        guard let first = words.first else { return .zero }
        return words.dropFirst().reduce(first.boundingBox) { $0.union($1.boundingBox) }
    }

    /// Left edge of the line. Used to tell description columns from price columns.
    public var minX: CGFloat { boundingBox.minX }

    /// Right edge of the line.
    public var maxX: CGFloat { boundingBox.maxX }

    /// Mean confidence of the words on this line.
    public var averageConfidence: Float {
        guard !words.isEmpty else { return 0 }
        return words.reduce(Float.zero) { $0 + $1.confidence } / Float(words.count)
    }
}
