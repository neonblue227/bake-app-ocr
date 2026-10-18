import BakeAppOCR
import Foundation

/// Renders a ``Receipt`` for humans and for machines.
///
/// Shared by the app's results pane, the "Copy summary" button and the CLI, so
/// what you see in the UI is exactly what you can paste into a bug report.
enum ReceiptSummary {

    // MARK: - Human readable

    static func text(for receipt: Receipt, includeRawLines: Bool = false) -> String {
        var out: [String] = []

        if let order = receipt.orderNumber {
            out.append("Order number : \(order.value)")
            out.append("               confidence \(percent(order.confidence)), matched \"\(order.label ?? "-")\"")
            out.append("               from: \(order.sourceLine)")
        } else {
            out.append("Order number : not found")
        }

        if let merchant = receipt.merchant { out.append("Merchant     : \(merchant)") }
        if let date = receipt.date { out.append("Date         : \(date)") }
        out.append("")

        out.append("Items (\(receipt.items.count))")
        if receipt.items.isEmpty {
            out.append("  none found")
        }
        for item in receipt.items {
            var row = "  \(quantity(item))  \(item.name.isEmpty ? "(no description)" : item.name)"
            if let unit = item.unitPrice, item.quantity != nil, item.quantity != 1 {
                row += "  @ \(money(unit))"
            }
            row += "  = \(money(item.lineTotal))"
            if !item.isInternallyConsistent {
                row += "   <- qty x unit does not match"
            }
            out.append(row)
        }
        out.append("")

        if receipt.subtotal != nil { out.append("Subtotal     : \(money(receipt.subtotal))") }
        if receipt.tax != nil { out.append("Tax          : \(money(receipt.tax))") }
        if receipt.tip != nil { out.append("Tip          : \(money(receipt.tip))") }
        out.append("Total        : \(money(receipt.total))")

        if !receipt.warnings.isEmpty {
            out.append("")
            out.append("Warnings")
            for warning in receipt.warnings { out.append("  - \(warning.message)") }
        }

        if receipt.orderNumberCandidates.count > 1 {
            out.append("")
            out.append("Other order-number candidates")
            for candidate in receipt.orderNumberCandidates.dropFirst() {
                out.append("  \(candidate.value)  [\(candidate.label)]  \(percent(candidate.confidence))")
            }
        }

        if includeRawLines {
            out.append("")
            out.append("Raw OCR lines")
            for (index, line) in receipt.rawLines.enumerated() {
                out.append(String(format: "  %2d  %@", index + 1, line))
            }
        }

        return out.joined(separator: "\n")
    }

    // MARK: - Machine readable

    static func json(for receipt: Receipt) -> String {
        var root: [String: Any] = [:]

        if let order = receipt.orderNumber {
            root["orderNumber"] = [
                "value": order.value,
                "confidence": order.confidence,
                "label": order.label ?? "",
                "sourceLine": order.sourceLine,
            ]
        } else {
            root["orderNumber"] = NSNull()
        }

        root["orderNumberCandidates"] = receipt.orderNumberCandidates.map { candidate in
            [
                "value": candidate.value,
                "confidence": candidate.confidence,
                "label": candidate.label,
            ] as [String: Any]
        }

        root["items"] = receipt.items.map { item in
            [
                "name": item.name,
                "quantity": number(item.quantity),
                "unitPrice": number(item.unitPrice),
                "lineTotal": number(item.lineTotal),
                "confidence": item.confidence,
            ] as [String: Any]
        }

        root["subtotal"] = number(receipt.subtotal)
        root["tax"] = number(receipt.tax)
        root["tip"] = number(receipt.tip)
        root["total"] = number(receipt.total)
        root["merchant"] = receipt.merchant ?? NSNull()
        root["date"] = receipt.date ?? NSNull()
        root["warnings"] = receipt.warnings.map(\.message)
        root["rawLines"] = receipt.rawLines

        guard
            let data = try? JSONSerialization.data(
                withJSONObject: root,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            ),
            let text = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return text
    }

    // MARK: - Formatting helpers

    private static let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    /// Quantities read better without trailing zeros: `2x`, not `2.00x`.
    private static let plainQuantity: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    static func money(_ value: Decimal?) -> String {
        guard let value else { return "-" }
        return currency.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
    }

    static func quantity(_ item: ReceiptItem) -> String {
        guard let quantity = item.quantity else { return "-" }
        let text = plainQuantity.string(from: NSDecimalNumber(decimal: quantity)) ?? "\(quantity)"
        return "\(text)x"
    }

    static func percent(_ confidence: Double) -> String {
        "\(Int((confidence * 100).rounded()))%"
    }

    private static func number(_ value: Decimal?) -> Any {
        guard let value else { return NSNull() }
        return NSDecimalNumber(decimal: value)
    }
}
