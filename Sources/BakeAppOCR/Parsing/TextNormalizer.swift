import Foundation

/// Cleans up OCR output so downstream matching can stay simple.
enum TextNormalizer {

    /// Collapses whitespace, strips dot leaders, and unifies the typographic
    /// variants OCR likes to emit.
    static func normalize(_ raw: String) -> String {
        var text = raw
        text = text.replacingOccurrences(of: "\u{00A0}", with: " ")  // non-breaking space
        text = text.replacingOccurrences(of: "\u{2013}", with: "-")  // en dash
        text = text.replacingOccurrences(of: "\u{2014}", with: "-")  // em dash
        text = text.replacingOccurrences(of: "\u{2018}", with: "'")
        text = text.replacingOccurrences(of: "\u{2019}", with: "'")
        text = text.replacingOccurrences(of: "\u{201C}", with: "\"")
        text = text.replacingOccurrences(of: "\u{201D}", with: "\"")
        text = text.replacingOccurrences(of: "\t", with: " ")
        // Dot leaders: `TOTAL AMT................. 60.31`
        text = Patterns.dotLeader.replacingMatches(in: text, with: " ")
        while text.contains("  ") {
            text = text.replacingOccurrences(of: "  ", with: " ")
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// Uppercased and whitespace-collapsed — the form matchers should use.
    static func canonical(_ raw: String) -> String {
        normalize(raw).uppercased()
    }

    /// Everything except letters and digits removed, uppercased.
    ///
    /// OCR splits and joins words (`ROUR DING` for `ROUNDING`), so fuzzy anchor
    /// matching compares this squashed form, which drops the space between them.
    static func squashed(_ raw: String) -> String {
        String(raw.uppercased().filter { $0.isLetter || $0.isNumber })
    }
}
