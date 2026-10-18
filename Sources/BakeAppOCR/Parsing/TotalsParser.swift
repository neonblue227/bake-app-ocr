import Foundation

/// Extracts subtotal, tax, tip and the grand total.
///
/// Totals are the messiest part of a receipt: labels wrap onto the next line,
/// leader dots pad the gap, and some lines carry two numbers where one is the
/// tax. This makes a best effort and prefers to return `nil` over a guess.
///
/// When several totals tie, the one closest to `subtotal + tax` wins, since
/// receipts restate the total in several ways but only one is the real one.
struct TotalsParser {

    struct Result: Equatable {
        var subtotal: Decimal?
        var tax: Decimal?
        var tip: Decimal?
        var total: Decimal?
    }

    /// A `TOTAL`-ish line we might pick as the grand total.
    private struct TotalCandidate {
        let index: Int
        let value: Decimal
        let strength: Int
    }

    func parse(from lines: [String]) -> Result {
        var result = Result()
        var totalCandidates: [TotalCandidate] = []

        for (index, rawLine) in lines.enumerated() {
            let line = TextNormalizer.canonical(rawLine)
            guard !line.isEmpty else { continue }

            let squashed = TextNormalizer.squashed(line)
            // `TOTAL QTY 9 327.00` is a count, not a total.
            if Patterns.nonTotalPhrases.contains(where: { squashed.contains($0) }) { continue }

            let values = valuesForLine(line, at: index, in: lines)
            guard let value = values.last else { continue }

            if FuzzyMatch.contains(Patterns.subtotalAnchor, inSquashed: squashed) {
                result.subtotal = value
                continue
            }
            if Patterns.taxAnchors.contains(where: { FuzzyMatch.contains($0, inSquashed: squashed) }),
               !FuzzyMatch.contains(Patterns.totalAnchor, inSquashed: squashed) {
                result.tax = value
                continue
            }
            if Patterns.tipAnchors.contains(where: { FuzzyMatch.contains($0, inSquashed: squashed) }) {
                result.tip = value
                continue
            }
            if FuzzyMatch.contains(Patterns.totalAnchor, inSquashed: squashed) {
                let chosen = values.count > 1 ? preferredOfMultiple(values) : value
                totalCandidates.append(
                    TotalCandidate(index: index, value: chosen, strength: strength(of: line))
                )
            }
        }

        result.total = selectTotal(from: totalCandidates, subtotal: result.subtotal, tax: result.tax)
        return result
    }

    // MARK: - Helpers

    /// A line such as `TOTAL : 106.10 6.37` is net-then-tax, so the smaller
    /// trailing number is not the amount owed.
    private func preferredOfMultiple(_ values: [Decimal]) -> Decimal {
        guard let first = values.first, let last = values.last else { return 0 }
        if first > 0, last * 2 < first { return first }
        return last
    }

    /// Values on a line, falling back to the next line when the label's own
    /// value wrapped: `TOTAL EXCLUDED TAX : 12.36` / `: 0.74`.
    private func valuesForLine(_ canonicalLine: String, at index: Int, in lines: [String]) -> [Decimal] {
        let values = Money.tokens(in: canonicalLine).map(\.value)
        if !values.isEmpty { return values }

        guard index + 1 < lines.count else { return [] }
        let next = TextNormalizer.canonical(lines[index + 1])
        guard next.filter(\.isLetter).isEmpty || next.hasPrefix(":") else { return [] }
        return Money.tokens(in: next).map(\.value)
    }

    /// How much a `TOTAL` line looks like the real amount owed.
    private func strength(of canonicalLine: String) -> Int {
        let squashed = TextNormalizer.squashed(canonicalLine)

        if squashed.hasPrefix("GRANDTOTAL") { return 100 }
        if squashed.hasPrefix("TOTALDUE") || squashed.hasPrefix("AMOUNTDUE") || squashed.hasPrefix("BALANCEDUE") { return 95 }
        if squashed.hasPrefix("TOTAL") {
            if squashed.contains("EXCLUD") { return 30 }
            if squashed.contains("DISCOUNT") { return 10 }
            if squashed.contains("GST") || squashed.contains("TAX") { return 40 }
            return 90
        }
        if squashed.contains("TOTAL") { return 50 }
        return 40
    }

    private func selectTotal(
        from candidates: [TotalCandidate],
        subtotal: Decimal?,
        tax: Decimal?
    ) -> Decimal? {
        guard !candidates.isEmpty else { return nil }

        let bestStrength = candidates.map(\.strength).max() ?? 0
        let strongest = candidates.filter { $0.strength == bestStrength }

        if let subtotal, let tax {
            let expected = subtotal + tax
            return strongest
                .min { abs($0.value - expected) < abs($1.value - expected) }?
                .value
        }

        // No subtotal to check against: the largest reading is the safest bet,
        // which also handles rounded-total lines.
        return strongest.map(\.value).max()
    }
}
