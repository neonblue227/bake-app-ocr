import Foundation

/// Finds the order number on a receipt.
///
/// Receipts label the same idea a dozen ways — `ORDER NO.`, `ORD #`, `INV#`,
/// `DOC NO`, `RECEIPT NO.`, `BILL NO` — and then pack other fields onto the
/// same line. This walks every known label, truncates the captured value at the
/// next field boundary, throws away decoys, and ranks what is left.
struct OrderNumberExtractor {

    struct Output {
        let best: ReceiptField?
        let candidates: [ReceiptCandidate]
    }

    /// Confidence normally given to a value found with no label at all.
    static let heuristicConfidence = 0.4

    func extract(from lines: [String]) -> Output {
        var candidates = labelledCandidates(from: lines)

        if candidates.isEmpty {
            candidates = heuristicCandidates(from: lines)
        }

        candidates.sort { $0.confidence > $1.confidence }

        // Collapse duplicates, keeping the strongest reading of each value.
        var seen = Set<String>()
        candidates = candidates.filter { seen.insert($0.value).inserted }

        let best = candidates.first.map {
            ReceiptField(
                value: $0.value,
                confidence: $0.confidence,
                sourceLine: $0.sourceLine,
                label: $0.label
            )
        }
        return Output(best: best, candidates: candidates)
    }

    // MARK: - Labelled pass

    private func labelledCandidates(from lines: [String]) -> [ReceiptCandidate] {
        var results: [ReceiptCandidate] = []

        for (index, rawLine) in lines.enumerated() {
            let line = TextNormalizer.canonical(rawLine)

            for label in Patterns.orderNumberLabels {
                guard let match = label.pattern.firstMatch(in: line),
                      let matchedRange = Range(match.range, in: line) else { continue }

                let remainder = String(line[matchedRange.upperBound...])

                if remainder.trimmingCharacters(in: .whitespaces).isEmpty {
                    // Label alone on its line: the value may sit on the next one.
                    guard index + 1 < lines.count else { continue }
                    let next = TextNormalizer.canonical(lines[index + 1])
                    guard !next.isEmpty else { continue }
                    // If the next line carries its own label it is a separate
                    // field, not a wrapped value.
                    let nextHasLabel = Patterns.orderNumberLabels.contains { $0.pattern.isMatch(next) }
                    guard !nextHasLabel else { continue }
                    if let candidate = makeCandidate(
                        value: ValueTruncation.truncate(next),
                        label: "\(label.name) (next line)",
                        tier: label.tier + 1,
                        sourceLine: rawLine
                    ) {
                        results.append(candidate)
                    }
                    continue
                }

                if let candidate = makeCandidate(
                    value: ValueTruncation.truncate(remainder),
                    label: label.name,
                    tier: label.tier,
                    sourceLine: rawLine
                ) {
                    results.append(candidate)
                }
            }
        }

        return results
    }

    private func makeCandidate(value rawValue: String, label: String, tier: Int, sourceLine: String) -> ReceiptCandidate? {
        let value = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "#: "))
        guard !value.isEmpty, value.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
        guard !Patterns.decoyValues.isMatch(value) else { return nil }

        var confidence = 1.0 - Double(tier) * 0.12

        if Patterns.alphanumericCode.isMatch(value) {
            confidence += 0.06
        }
        // A short value is only credible behind a strong label. `ORD #50` is a
        // real McDonald's order number; `REF: 7` usually is not.
        if value.count <= 2 && tier >= 2 {
            confidence -= 0.25
        }
        if value.count >= 4 && value.allSatisfy(\.isNumber) {
            confidence += 0.03
        }

        return ReceiptCandidate(
            value: value,
            confidence: min(max(confidence, 0.05), 1.0),
            label: label,
            sourceLine: sourceLine
        )
    }

    // MARK: - Unlabelled fallback

    /// Last resort: a long identifier near the top that is not on a price line.
    ///
    /// Handles terminal traces such as `SH01 ZK09 T4 R000027830`, which carry no
    /// label at all. Deliberately low confidence — the caller should confirm.
    private func heuristicCandidates(from lines: [String]) -> [ReceiptCandidate] {
        var results: [ReceiptCandidate] = []

        for rawLine in lines.prefix(12) {
            let line = TextNormalizer.canonical(rawLine)
            guard !line.isEmpty else { continue }
            guard Money.tokens(in: line).isEmpty else { continue }
            guard !Patterns.nonItemLine.isMatch(line) else { continue }

            for token in line.split(separator: " ").map(String.init) {
                guard Patterns.bareIdentifier.isMatch(token) else { continue }
                guard !Patterns.decoyValues.isMatch(token) else { continue }
                results.append(
                    ReceiptCandidate(
                        value: token,
                        confidence: Self.heuristicConfidence,
                        label: "heuristic",
                        sourceLine: rawLine
                    )
                )
            }
        }

        return results
    }
}
