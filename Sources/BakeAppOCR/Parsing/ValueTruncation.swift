import Foundation

/// Cuts a captured value at the next field on the line.
///
/// This is the single most important rule for order numbers. Real receipts pack
/// several fields onto one line:
///
/// ```text
/// DOC NO CS00031663 DATE 25/12/2018   ->  CS00031663
/// RECEIPT NO.:003-1220815 PAX: 1      ->  003-1220815
/// ORD #50 -REG #19- 18/01/2018        ->  50
/// ORDER NO. 1000219 11/03/2018 06:20  ->  1000219
/// ```
///
/// A plain greedy capture returns the whole tail, so every label extractor
/// routes its remainder through here.
enum ValueTruncation {

    /// Characters that only ever decorate the edges of an identifier.
    private static let edgeCharacters = CharacterSet(charactersIn: " \t:-#.*/|,\u{00B7}")

    static func truncate(_ raw: String) -> String {
        var cut = raw.endIndex

        if let match = Patterns.valueStoppers.firstMatch(in: raw),
           let range = Range(match.range, in: raw) {
            cut = min(cut, range.lowerBound)
        }
        if let match = Patterns.date.firstMatch(in: raw),
           let range = Range(match.range(at: 1), in: raw) {
            cut = min(cut, range.lowerBound)
        }
        if let match = Patterns.time.firstMatch(in: raw),
           let range = Range(match.range, in: raw) {
            cut = min(cut, range.lowerBound)
        }

        return String(raw[raw.startIndex..<cut]).trimmingCharacters(in: edgeCharacters)
    }
}
