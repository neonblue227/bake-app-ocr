import Foundation

/// Small wrapper so patterns read cleanly at the call site.
struct Regex {
    private let expression: NSRegularExpression

    init(_ pattern: String, options: NSRegularExpression.Options = [.caseInsensitive]) {
        do {
            expression = try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            fatalError("Invalid regular expression '\(pattern)': \(error)")
        }
    }

    func firstMatch(in string: String) -> NSTextCheckingResult? {
        expression.firstMatch(in: string, options: [], range: string.fullRange)
    }

    func allMatches(in string: String) -> [NSTextCheckingResult] {
        expression.matches(in: string, options: [], range: string.fullRange)
    }

    func isMatch(_ string: String) -> Bool {
        firstMatch(in: string) != nil
    }

    func replacingMatches(in string: String, with template: String) -> String {
        expression.stringByReplacingMatches(
            in: string,
            options: [],
            range: string.fullRange,
            withTemplate: template
        )
    }
}

extension String {
    var fullRange: NSRange { NSRange(startIndex..<endIndex, in: self) }

    func substring(with range: NSRange) -> String? {
        guard let range = Range(range, in: self) else { return nil }
        return String(self[range])
    }
}

extension NSTextCheckingResult {
    /// The text of a capture group, or the whole match when `group` is `0`.
    func text(in string: String, group: Int = 0) -> String? {
        guard group < numberOfRanges else { return nil }
        return string.substring(with: range(at: group))
    }
}
