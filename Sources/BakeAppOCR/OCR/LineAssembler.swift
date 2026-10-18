import CoreGraphics
import Foundation

/// Groups loose OCR words back into visual lines.
///
/// Words join a line when their vertical centres are within a tolerance that
/// scales with the text height. Scaling matters: a receipt's header is set much
/// larger than its fine print, and a fixed pixel threshold would merge the two.
public enum LineAssembler {

    /// How far apart two words' centres may be and still share a line,
    /// expressed as a multiple of the average glyph height.
    static let verticalToleranceFactor: CGFloat = 0.6

    /// Absolute floor for the tolerance, so tiny text still groups sensibly.
    static let minimumTolerance: CGFloat = 0.008

    public static func assemble(_ words: [RecognizedWord]) -> [RecognizedLine] {
        guard !words.isEmpty else { return [] }

        // Vision's origin is bottom-left, so a larger midY is higher on the page.
        let sorted = words.sorted { lhs, rhs in
            let difference = lhs.boundingBox.midY - rhs.boundingBox.midY
            if abs(difference) > 0.0005 { return difference > 0 }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }

        var groups: [[RecognizedWord]] = []
        var current: [RecognizedWord] = []

        for word in sorted {
            guard !current.isEmpty else {
                current = [word]
                continue
            }

            let meanY = current.reduce(CGFloat.zero) { $0 + $1.boundingBox.midY } / CGFloat(current.count)
            let meanHeight = current.reduce(CGFloat.zero) { $0 + $1.boundingBox.height } / CGFloat(current.count)
            let tolerance = max(verticalToleranceFactor * meanHeight, minimumTolerance)

            if abs(word.boundingBox.midY - meanY) <= tolerance {
                current.append(word)
            } else {
                groups.append(current)
                current = [word]
            }
        }
        if !current.isEmpty { groups.append(current) }

        return groups.map { group in
            RecognizedLine(words: group.sorted { $0.boundingBox.minX < $1.boundingBox.minX })
        }
    }
}
