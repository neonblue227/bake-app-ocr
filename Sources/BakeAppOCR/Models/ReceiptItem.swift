import Foundation

/// One purchased line item.
public struct ReceiptItem: Equatable {
    public let name: String
    public let quantity: Decimal?
    public let unitPrice: Decimal?
    public let lineTotal: Decimal?
    /// `0...1` — how confident the parser is that this is a real item line.
    public let confidence: Double
    /// The OCR lines this item was assembled from. Handy when tuning.
    public let sourceLines: [String]

    public init(
        name: String,
        quantity: Decimal?,
        unitPrice: Decimal?,
        lineTotal: Decimal?,
        confidence: Double,
        sourceLines: [String]
    ) {
        self.name = name
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.lineTotal = lineTotal
        self.confidence = confidence
        self.sourceLines = sourceLines
    }

    /// `true` when `quantity * unitPrice` agrees with `lineTotal`.
    public var isInternallyConsistent: Bool {
        guard let quantity, let unitPrice, let lineTotal, quantity > 0 else { return true }
        return abs(quantity * unitPrice - lineTotal) <= Money.tolerance
    }
}
