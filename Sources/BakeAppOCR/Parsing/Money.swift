import Foundation

/// An amount found on a line, with where it was found.
struct MoneyToken: Equatable {
    let value: Decimal
    let range: NSRange
}

/// Currency parsing that copes with the separator conventions receipts use.
enum Money {

    /// Two cents. The slack allowed when comparing amounts that were rounded
    /// on different lines of the same receipt.
    static let tolerance = Decimal(sign: .plus, exponent: -2, significand: 2)

    /// Parses an amount such as `19.00`, `1,234.56`, `1.234,56` or `9.000`.
    ///
    /// Receipts mix conventions freely, so the rule is: a single separator
    /// followed by one to three digits is the decimal separator; anything else
    /// is a thousands separator.
    static func parse(_ raw: String) -> Decimal? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let isNegative = text.hasPrefix("-")
        text = text.filter { $0.isNumber || $0 == "." || $0 == "," }

        guard !text.isEmpty, text.contains(where: \.isNumber) else { return nil }

        let dotCount = text.filter { $0 == "." }.count
        let commaCount = text.filter { $0 == "," }.count
        var normalized = text

        if dotCount > 0 && commaCount > 0 {
            // Whichever separator comes last is the decimal one.
            let lastDot = text.lastIndex(of: ".")!
            let lastComma = text.lastIndex(of: ",")!
            if lastDot > lastComma {
                normalized = text.replacingOccurrences(of: ",", with: "")
            } else {
                normalized = text
                    .replacingOccurrences(of: ".", with: "")
                    .replacingOccurrences(of: ",", with: ".")
            }
        } else if dotCount + commaCount > 1 {
            // Repeated separators can only be grouping separators.
            normalized = text
                .replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: ".", with: "")
        } else if let separator = text.firstIndex(where: { $0 == "." || $0 == "," }) {
            let fraction = text[text.index(after: separator)...]
            if fraction.count > 3 {
                normalized = text
                    .replacingOccurrences(of: ",", with: "")
                    .replacingOccurrences(of: ".", with: "")
            } else {
                normalized = text.replacingOccurrences(of: ",", with: ".")
            }
        }

        guard var value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        if isNegative { value = -value }
        return value
    }

    /// The monetary tokens on a line, left to right.
    ///
    /// Percentage values are skipped so `@DISC 10.00%` is not read as a price.
    static func tokens(in line: String) -> [MoneyToken] {
        Patterns.money.allMatches(in: line).compactMap { match in
            let followingIndex = match.range.location + match.range.length
            if let following = line.substring(with: NSRange(location: followingIndex, length: 1)),
               following == "%" {
                return nil
            }
            guard let raw = match.text(in: line), let value = parse(raw) else { return nil }
            return MoneyToken(value: value, range: match.range)
        }
    }

    /// Rounds to two decimal places, so an inferred unit price stays readable.
    static func rounded(_ value: Decimal) -> Decimal {
        var input = value
        var output = Decimal()
        NSDecimalRound(&output, &input, 2, .plain)
        return output
    }
}
