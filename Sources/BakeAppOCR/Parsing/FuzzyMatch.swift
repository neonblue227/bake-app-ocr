import Foundation

/// Approximate matching for keywords that OCR has mangled.
///
/// Real scans produce `ROUR DING ADJUSTMENT` for `ROUNDING ADJUSTMENT` and
/// `FLEASE COME AOSIN` for `PLEASE COME AGAIN`. Exact substring tests fail on
/// those, so anchors are matched against the squashed line with a small edit
/// budget. Squashing first is what makes it work: `ROUR DING` becomes
/// `ROURDING`, one edit away from `ROUNDING`.
enum FuzzyMatch {

    /// `true` when `needle` appears in an already-squashed haystack, allowing
    /// up to `maxDistance` single-character edits.
    ///
    /// Needles of three characters or fewer must match exactly. They carry too
    /// little signal to tolerate edits: with one edit allowed, `TAX` would match
    /// `TAL`, and the word `TOTAL` contains exactly that.
    static func contains(_ needle: String, inSquashed squashedHaystack: String, maxDistance: Int = 1) -> Bool {
        let target = TextNormalizer.squashed(needle)
        guard !target.isEmpty, !squashedHaystack.isEmpty else { return false }

        if squashedHaystack.contains(target) { return true }

        let budget = target.count <= 3 ? 0 : maxDistance
        guard budget > 0 else { return false }

        return windows(of: squashedHaystack, length: target.count)
            .contains { levenshtein($0, target) <= budget }
    }

    /// Levenshtein edit distance.
    static func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)

        if left.isEmpty { return right.count }
        if right.isEmpty { return left.count }

        var previous = Array(0...right.count)
        var current = [Int](repeating: 0, count: right.count + 1)

        for i in 1...left.count {
            current[0] = i
            for j in 1...right.count {
                let substitutionCost = left[i - 1] == right[j - 1] ? 0 : 1
                current[j] = min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + substitutionCost
                )
            }
            swap(&previous, &current)
        }
        return previous[right.count]
    }

    /// Every contiguous run of `length` characters in `text`.
    static func windows(of text: String, length: Int) -> [String] {
        let characters = Array(text)
        guard length > 0, characters.count >= length else { return [] }
        return (0...(characters.count - length)).map { start in
            String(characters[start..<(start + length)])
        }
    }
}
