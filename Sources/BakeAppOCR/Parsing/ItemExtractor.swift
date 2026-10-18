import Foundation

/// Pulls the purchased items out of a receipt.
///
/// The hard part is not finding prices — it is deciding which text belongs to
/// which item. Real receipts put the description on either side of the numbers:
///
/// ```text
/// 2 CHICMCMUFFIN 11.00      <- name before the price
/// FG-A00019 1 1.50 1.50 SR
/// GREEN TEA                 <- name after the price
/// ```
///
/// so names are merged from both directions, and a price line whose own text is
/// only a product code will adopt the adjacent description line.
struct ItemExtractor {

    private enum Segment {
        case text(String)
        case priced(line: String, inlineName: String, amounts: [Decimal], quantity: Decimal?, unitPrice: Decimal?)
    }

    func extract(from lines: [String]) -> [ReceiptItem] {
        let region = itemRegion(from: lines)
        return merge(segments(from: region))
    }

    // MARK: - Region selection

    /// The lines between the column header and the first totals row.
    ///
    /// Restricting to that window is what keeps addresses, footers and tax
    /// summaries from being mistaken for items.
    private func itemRegion(from lines: [String]) -> [String] {
        let canonical = lines.map { TextNormalizer.canonical($0) }

        var start = 0
        if let headerIndex = canonical.firstIndex(where: { Patterns.itemTableHeader.isMatch($0) }) {
            start = headerIndex + 1
        }

        var end = lines.count
        if start < lines.count {
            for index in start..<lines.count where Patterns.itemBlockTerminator.isMatch(canonical[index]) {
                end = index
                break
            }
        }

        guard start < end else { return [] }
        return Array(lines[start..<end])
    }

    // MARK: - Classification

    private func segments(from lines: [String]) -> [Segment] {
        var result: [Segment] = []

        for rawLine in lines {
            let line = TextNormalizer.normalize(rawLine)
            guard !line.isEmpty else { continue }

            let canonical = line.uppercased()
            if Patterns.nonItemLine.isMatch(canonical) { continue }
            if Patterns.itemTableHeader.isMatch(canonical) { continue }

            let money = Money.tokens(in: line)
            guard looksLikePriceLine(line, amounts: money) else {
                result.append(.text(line))
                continue
            }

            let inlineName = describe(line, excluding: money.map(\.range))
            var quantity: Decimal?
            var unitPrice: Decimal?

            if let match = Patterns.quantityTimesPrice.firstMatch(in: canonical),
               let quantityText = match.text(in: canonical, group: 1),
               let parsedQuantity = Decimal(string: quantityText),
               let unitText = match.text(in: canonical, group: 2),
               let parsedUnit = Money.parse(unitText) {
                quantity = parsedQuantity
                unitPrice = parsedUnit
            } else {
                quantity = inferQuantity(from: canonical, moneyRanges: money.map(\.range))
                if money.count >= 2 {
                    unitPrice = money[money.count - 2].value
                }
            }

            let lineTotal = money.last?.value
            if unitPrice == nil, let lineTotal {
                unitPrice = (quantity.map { $0 > 0 ? Money.rounded(lineTotal / $0) : lineTotal }) ?? lineTotal
            }

            result.append(
                .priced(
                    line: line,
                    inlineName: inlineName,
                    amounts: money.map(\.value),
                    quantity: quantity,
                    unitPrice: unitPrice
                )
            )
        }

        return result
    }

    /// Guards against reading a measurement inside a description as a price.
    ///
    /// `TRAILING SKT 5GN+SP 3X1.25MM CABLE 2 *S` contains `1.25`, but prices are
    /// right-aligned, so text following the number means it was not a price.
    private func looksLikePriceLine(_ line: String, amounts: [MoneyToken]) -> Bool {
        guard let last = amounts.last else { return false }
        guard amounts.count == 1 else { return true }

        let end = last.range.location + last.range.length
        let tailLength = max(0, line.utf16.count - end)
        let tail = line.substring(with: NSRange(location: end, length: tailLength)) ?? ""
        // A trailing tax code such as `SR` is fine; a sentence is not.
        return tail.filter(\.isLetter).count <= 3
    }

    /// The quantity for `4 X 2.80`-style lines where the `X` is absent.
    ///
    /// Takes the last small integer before the first price, which is the
    /// quantity column on a normal receipt.
    private func inferQuantity(from line: String, moneyRanges: [NSRange]) -> Decimal? {
        let firstAmountStart = moneyRanges.map { $0.location }.min() ?? line.utf16.count
        var quantity: Decimal?

        for match in Patterns.standaloneInteger.allMatches(in: line) {
            guard match.range.location < firstAmountStart else { break }
            guard let text = match.text(in: line),
                  let value = Decimal(string: text),
                  value >= 1, value <= 99 else { continue }
            quantity = value
        }

        return quantity
    }

    /// The description text left on a price line once amounts are removed.
    ///
    /// Returns an empty string when the line carries only codes and quantities,
    /// which is the signal to adopt an adjacent line as the name.
    private func describe(_ line: String, excluding moneyRanges: [NSRange]) -> String {
        let tokens = Patterns.token.allMatches(in: line).compactMap { match -> (text: String, range: NSRange)? in
            guard let text = match.text(in: line) else { return nil }
            return (text, match.range)
        }

        var kept: [String] = []
        for (offset, token) in tokens.enumerated() {
            if moneyRanges.contains(where: { NSIntersectionRange($0, token.range).length > 0 }) { continue }

            let upper = token.text.uppercased()
            if Patterns.ignorableTokens.contains(upper) { continue }
            // Quantities, barcodes and product codes.
            if token.text.allSatisfy(\.isNumber) { continue }
            if token.text.contains(where: \.isNumber), Patterns.productCode.isMatch(upper) { continue }
            if offset == tokens.count - 1, Patterns.trailingTaxCodes.contains(upper) { continue }

            kept.append(token.text)
        }

        return kept.joined(separator: " ")
    }

    // MARK: - Name merging

    private func merge(_ segments: [Segment]) -> [ReceiptItem] {
        var items: [ReceiptItem] = []
        var buffer: [String] = []
        var index = 0

        while index < segments.count {
            switch segments[index] {
            case .text(let text):
                buffer.append(text)
                index += 1

            case .priced(let line, let inlineName, let amounts, let quantity, let unitPrice):
                let inlineIsName = Self.isMeaningfulName(inlineName)
                let bufferIsName = buffer.contains { Self.isMeaningfulName($0) }

                var nameParts: [String] = []
                var sourceLines: [String] = []

                if bufferIsName || (buffer.isEmpty == false && inlineIsName == false) {
                    nameParts.append(contentsOf: buffer)
                    sourceLines.append(contentsOf: buffer)
                }
                if !inlineName.isEmpty { nameParts.append(inlineName) }
                sourceLines.append(line)

                var next = index + 1
                var adoptedFollowingLine = false

                // Nothing on this line or above names the item, so the
                // description must be the line just below it.
                if !inlineIsName && !bufferIsName {
                    while next < segments.count {
                        guard case .text(let following) = segments[next], !following.isEmpty else { break }
                        nameParts.append(following)
                        sourceLines.append(following)
                        adoptedFollowingLine = true
                        next += 1
                    }
                }

                buffer.removeAll()
                index = next

                let name = Self.cleanName(nameParts)
                guard !name.isEmpty || !amounts.isEmpty else { continue }

                var confidence = 0.55
                if quantity != nil && unitPrice != nil { confidence += 0.15 }
                if Self.isMeaningfulName(name) { confidence += 0.15 }
                if !amounts.isEmpty { confidence += 0.05 }
                if adoptedFollowingLine { confidence -= 0.10 }

                items.append(
                    ReceiptItem(
                        name: name,
                        quantity: quantity,
                        unitPrice: unitPrice,
                        lineTotal: amounts.last,
                        confidence: min(max(confidence, 0.05), 1.0),
                        sourceLines: sourceLines
                    )
                )
            }
        }

        // A description with no price after it, such as the drink line on many
        // fast-food receipts: `1 L COKE`. Keep it, with no amount, rather than
        // silently dropping an item the customer paid for.
        if !buffer.isEmpty {
            let name = Self.cleanName(buffer.map { describe($0, excluding: []) })
            if Self.isMeaningfulName(name) {
                items.append(
                    ReceiptItem(
                        name: name,
                        quantity: nil,
                        unitPrice: nil,
                        lineTotal: nil,
                        confidence: 0.4,
                        sourceLines: buffer
                    )
                )
            }
        }

        return items
    }

    /// `true` when the text reads like a description rather than a bare code.
    static func isMeaningfulName(_ text: String) -> Bool {
        text.split(separator: " ").contains { token in
            let word = String(token)
            guard word.filter(\.isLetter).count >= 3 else { return false }
            if word.contains(where: \.isNumber), Patterns.productCode.isMatch(word.uppercased()) {
                return false
            }
            return true
        }
    }

    static func cleanName(_ parts: [String]) -> String {
        parts
            .joined(separator: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t:-#.*/|,\u{00B7}"))
    }
}
