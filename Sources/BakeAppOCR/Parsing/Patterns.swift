import Foundation

/// A labelled pattern that can introduce an order number.
struct OrderNumberLabel {
    let name: String
    let pattern: Regex
    /// Lower is a stronger signal. `ORDER` beats `REF`.
    let tier: Int
}

/// Every regex and keyword list that drives parsing.
///
/// This is deliberately one file. When a receipt format breaks the parser, a
/// new entry here is usually the whole fix.
enum Patterns {

    // MARK: - Tokens

    /// A monetary token. Requiring a decimal part is what stops barcodes and
    /// quantities from being read as prices.
    static let money = Regex(#"-?\d[\d,]*(?:[.,]\d{2,4})"#)

    /// `25/12/2018`, `2018-12-25`, `1.2.18`.
    static let date = Regex(#"(?:^|[\s(:])(\d{1,2}[/\-.]\d{1,2}[/\-.]\d{2,4}|\d{4}[/\-.]\d{1,2}[/\-.]\d{1,2})(?=[\s)|]|$)"#)

    /// `09:12`, `10:27:03 PM`.
    static let time = Regex(#"(?:^|\s)(\d{1,2}:\d{2}(?::\d{2})?\s*(?:[AP]\.?M\.?)?)(?=\s|$)"#)

    /// Runs of four or more dots/dashes used as leader lines. Note the ICU
    /// escape `\u00B7` rather than Swift's `\u{00B7}`.
    static let dotLeader = Regex(#"[.\u00B7\-_]{4,}"#)

    /// Any non-whitespace run: one "word" for name building.
    static let token = Regex(#"\S+"#)

    // MARK: - Order numbers

    /// Field labels that introduce an order number, strongest first.
    ///
    /// The trailing `[\s:#.\-]*` swallows the separator soup receipts use —
    /// `NO. :`, `#:`, `NO ` — so the captured remainder starts at the value.
    static let orderNumberLabels: [OrderNumberLabel] = [
        OrderNumberLabel(name: "ORDER", pattern: Regex(#"\border[\s]*(?:no|num|number|id)?[\s:#.\-]*"#), tier: 0),
        OrderNumberLabel(name: "ORD", pattern: Regex(#"\bord[\s]*[:#][\s:#.\-]*"#), tier: 0),
        OrderNumberLabel(name: "TAX INVOICE", pattern: Regex(#"\btax[\s]*inv(?:oice)?[\s]*(?:no|num|number)?[\s:#.\-]*"#), tier: 1),
        OrderNumberLabel(name: "INVOICE", pattern: Regex(#"\binv(?:oice)?[\s]*(?:no|num|number|id)?[\s:#.\-]*"#), tier: 1),
        OrderNumberLabel(name: "BILL", pattern: Regex(#"\bbill[\s]*(?:no|num|number|id)?[\s:#.\-]*"#), tier: 2),
        OrderNumberLabel(name: "CHECK", pattern: Regex(#"\bch[ea]ck[\s]*(?:no|num|number|id)?[\s:#.\-]*"#), tier: 2),
        OrderNumberLabel(name: "RECEIPT", pattern: Regex(#"\breceipt[\s]*(?:no|num|number|id)?[\s:#.\-]*"#), tier: 3),
        OrderNumberLabel(name: "DOCUMENT", pattern: Regex(#"\bdoc(?:ument)?[\s]*(?:no|num|number|id)?[\s:#.\-]*"#), tier: 4),
        OrderNumberLabel(name: "TRANSACTION", pattern: Regex(#"\b(?:trans|transaction|ref|reference|slip)[\s]*(?:no|num|number|id)?[\s:#.\-]*"#), tier: 5),
    ]

    /// Tokens that mean "stop reading the value here".
    ///
    /// Without this, `DOC NO CS00031663 DATE 25/12/2018` yields the whole tail
    /// as the document number.
    static let valueStoppers = Regex(
        #"\b(?:date|time|cashier|operator|pax|pax\(s\)|table|tab|tel|telephone|room|station|reg|register|cust|customer|server|guest|cover|covers|terminal|term|amount|amt|total|subtotal|balance|change|card|visa|mastercard|amex|debit|credit|trace|seq|shift|store|branch|member|mb|token|order|invoice|receipt|bill|tag|status|type|of|no)\b"#
    )

    /// Values that are never order numbers, even when a label says otherwise.
    /// Rejects single digits, bare years, and clock times.
    static let decoyValues = Regex(#"^(?:\d|(?:1[89]|20)\d{2}|(?:[01]?\d|2[0-3]):[0-5]\d.*)$"#)

    /// A value carrying a vendor prefix: `CS00031663`, `OR18032702170334`,
    /// `POS01/00012379`, `REC-0015016`.
    static let alphanumericCode = Regex(#"^[A-Z]{2,4}[\s\-/]?\d{3,}[A-Z0-9\-/ ]*$"#)

    /// Fallback with no label at all: a long identifier such as `R000027830`.
    static let bareIdentifier = Regex(#"^[A-Z]{1,4}[\-]?\d{4,}$"#)

    // MARK: - Item table

    /// A column header row such as `ITEM QTY U.PRICE AMOUNT TAX`.
    static let itemTableHeader = Regex(
        #"(?=.*\b(?:item|items|desc|description)\b)(?=.*\b(?:qty|quantity|amount|amt|price|total)\b).+"#
    )

    /// A line that ends the item block.
    static let itemBlockTerminator = Regex(
        #"\b(?:sub[\s]*total|total|grand[\s]*total|amount[\s]*due|balance|tax|gst|vat|hst|service|tip|gratuity|discount|rounding|change|cash|tender|visa|mastercard|amex|debit|credit|payment|paid)\b"#
    )

    /// Lines that look like prices but are not items.
    static let nonItemLine = Regex(
        #"\b(?:sub[\s]*total|grand[\s]*total|total|amount[\s]*due|balance|tax|gst|vat|hst|service|charge|tip|gratuity|discount|rounding|change|cash|tendered|tender|visa|mastercard|amex|debit|credit|payment|paid|thank|coupon|voucher|loyalty|points|refund|exchange)\b|@\s*disc"#
    )

    /// Anchors for the totals pass, squashed before comparison.
    static let subtotalAnchor = "SUBTOTAL"
    static let totalAnchor = "TOTAL"
    static let taxAnchors = ["TAX", "GST", "VAT", "HST", "SALESTAX"]
    static let tipAnchors = ["TIP", "GRATUITY", "SERVICECHARGE"]

    /// Phrases that look like a total but are a count.
    static let nonTotalPhrases = ["TOTALQTY", "TOTALITEMS", "TOTALCOUNT", "TOTALSAVINGS"]

    // MARK: - Item lines

    /// `4 X 2.80` — quantity times unit price, the most reliable item shape.
    static let quantityTimesPrice = Regex(#"(\d{1,3})\s*[xX*@]\s*(\d[\d,]*(?:[.,]\d{2,4}))"#)

    /// A standalone small integer, i.e. a quantity sitting in its own column.
    /// The lookarounds keep it out of barcodes such as `9555221301081`.
    static let standaloneInteger = Regex(#"(?<![\d.,])(\d{1,3})(?![\d.,])"#)

    /// A product code leading a line: `FG-A00019`, `E8318`, `WA45/2A`.
    static let productCode = Regex(#"^[A-Z]{1,4}[\-/]?[A-Z0-9]{2,}$"#)

    /// Tokens to ignore when building an item name.
    ///
    /// Single letters like `L` are deliberately absent: `1 L COKE` is a large
    /// coke, not a quantity followed by a unit.
    static let ignorableTokens: Set<String> = [
        "X", "*", "@", "-", "/", "|", "+",
        "PC", "PCS", "EA", "EACH", "CT", "PK", "PKG", "BOX", "UN", "UNIT", "SET",
        "KG", "MG", "ML", "CL", "OZ", "LB", "GAL", "QTY",
    ]

    /// Tax codes that trail an item line and must not join the name.
    static let trailingTaxCodes: Set<String> = ["SR", "S", "Z", "A", "B", "G", "N", "TX", "T"]
}
