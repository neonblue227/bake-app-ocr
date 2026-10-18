import Foundation

/// Turns OCR lines into a ``Receipt``.
///
/// This is the testable core of the package: it takes plain strings, so the
/// whole parser can be exercised without an image or a device.
public struct ReceiptParser {

    public init() {}

    /// Parses already-separated lines of receipt text.
    ///
    /// Use this when you have your own OCR output, or in tests.
    public func parse(lines rawLines: [String]) -> Receipt {
        let lines = rawLines
            .map { TextNormalizer.normalize($0) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return .empty }

        let orderNumber = OrderNumberExtractor().extract(from: lines)
        let items = ItemExtractor().extract(from: lines)
        let totals = TotalsParser().parse(from: lines)

        return Receipt(
            orderNumber: orderNumber.best,
            orderNumberCandidates: orderNumber.candidates,
            items: items,
            subtotal: totals.subtotal,
            tax: totals.tax,
            tip: totals.tip,
            total: totals.total,
            date: Self.date(in: lines),
            merchant: Self.merchant(in: lines),
            warnings: Self.warnings(
                orderNumber: orderNumber.best,
                items: items,
                totals: totals
            ),
            rawLines: lines
        )
    }

    // MARK: - Derived fields

    static func date(in lines: [String]) -> String? {
        for line in lines {
            let canonical = TextNormalizer.canonical(line)
            guard let match = Patterns.date.firstMatch(in: canonical) else { continue }
            if let value = match.text(in: canonical, group: 1) { return value }
        }
        return nil
    }

    /// The first line that reads like a business name.
    static func merchant(in lines: [String]) -> String? {
        for line in lines.prefix(6) {
            let canonical = TextNormalizer.canonical(line)
            guard canonical.filter(\.isLetter).count >= 3 else { continue }
            guard !Patterns.nonItemLine.isMatch(canonical) else { continue }
            guard !Patterns.itemTableHeader.isMatch(canonical) else { continue }
            guard Money.tokens(in: canonical).isEmpty else { continue }
            guard Patterns.orderNumberLabels.allSatisfy({ !$0.pattern.isMatch(canonical) }) else { continue }
            guard !canonical.contains("TEL") else { continue }
            return line
        }
        return nil
    }

    static func warnings(
        orderNumber: ReceiptField?,
        items: [ReceiptItem],
        totals: TotalsParser.Result
    ) -> [ReceiptWarning] {
        var warnings: [ReceiptWarning] = []

        if let orderNumber {
            if orderNumber.confidence < 0.5 {
                warnings.append(.orderNumberLowConfidence(orderNumber.confidence))
            }
        } else {
            warnings.append(.orderNumberNotFound)
        }

        if items.isEmpty { warnings.append(.noItemsFound) }
        if totals.total == nil { warnings.append(.missingTotal) }
        if totals.subtotal == nil { warnings.append(.missingSubtotal) }

        let itemsTotal = items.compactMap(\.lineTotal).reduce(Decimal.zero, +)
        if let reference = totals.subtotal ?? totals.total, !items.isEmpty, itemsTotal > 0 {
            if abs(itemsTotal - reference) > Money.tolerance {
                warnings.append(.itemTotalMismatch(itemsTotal: itemsTotal, receiptTotal: reference))
            }
        }

        return warnings
    }
}
