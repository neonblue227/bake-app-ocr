import Foundation

/// Something the parser thinks you should know about.
public enum ReceiptWarning: Equatable {
    case orderNumberNotFound
    case orderNumberLowConfidence(Double)
    case noItemsFound
    /// The sum of the item totals does not agree with the receipt's own totals.
    case itemTotalMismatch(itemsTotal: Decimal, receiptTotal: Decimal)
    case missingTotal
    case missingSubtotal

    public var message: String {
        switch self {
        case .orderNumberNotFound:
            return "No order number could be identified."
        case .orderNumberLowConfidence(let confidence):
            let percent = Int((confidence * 100).rounded())
            return "Order number was found by a weak heuristic (confidence \(percent)%)."
        case .noItemsFound:
            return "No line items could be identified."
        case .itemTotalMismatch(let itemsTotal, let receiptTotal):
            return "Item totals sum to \(itemsTotal) but the receipt says \(receiptTotal)."
        case .missingTotal:
            return "No grand total was found on the receipt."
        case .missingSubtotal:
            return "No subtotal was found on the receipt."
        }
    }
}

/// The parsed receipt.
///
/// Every field is optional: the parser would rather return `nil` than invent a
/// value. Check ``warnings`` to see what it was unsure about.
public struct Receipt: Equatable {
    public let orderNumber: ReceiptField?
    /// Every order-number candidate, best first.
    public let orderNumberCandidates: [ReceiptCandidate]
    public let items: [ReceiptItem]
    public let subtotal: Decimal?
    public let tax: Decimal?
    public let tip: Decimal?
    public let total: Decimal?
    public let date: String?
    public let merchant: String?
    public let warnings: [ReceiptWarning]
    /// Every OCR line in reading order. Useful when tuning the parser.
    public let rawLines: [String]

    public init(
        orderNumber: ReceiptField?,
        orderNumberCandidates: [ReceiptCandidate],
        items: [ReceiptItem],
        subtotal: Decimal?,
        tax: Decimal?,
        tip: Decimal?,
        total: Decimal?,
        date: String?,
        merchant: String?,
        warnings: [ReceiptWarning],
        rawLines: [String]
    ) {
        self.orderNumber = orderNumber
        self.orderNumberCandidates = orderNumberCandidates
        self.items = items
        self.subtotal = subtotal
        self.tax = tax
        self.tip = tip
        self.total = total
        self.date = date
        self.merchant = merchant
        self.warnings = warnings
        self.rawLines = rawLines
    }

    /// An empty receipt, returned when OCR produced nothing usable.
    public static let empty = Receipt(
        orderNumber: nil,
        orderNumberCandidates: [],
        items: [],
        subtotal: nil,
        tax: nil,
        tip: nil,
        total: nil,
        date: nil,
        merchant: nil,
        warnings: [.orderNumberNotFound, .noItemsFound, .missingTotal],
        rawLines: []
    )
}
