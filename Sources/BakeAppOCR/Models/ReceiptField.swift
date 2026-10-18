import Foundation

/// A value extracted from the receipt, plus how much we trust it.
public struct ReceiptField: Equatable {
    public let value: String
    /// `0...1`. Treat anything under `0.5` as worth confirming with the user.
    public let confidence: Double
    /// The OCR line the value came from, for debugging.
    public let sourceLine: String
    /// The label that matched, e.g. `ORDER` or `INVOICE`.
    public let label: String?

    public init(value: String, confidence: Double, sourceLine: String, label: String?) {
        self.value = value
        self.confidence = confidence
        self.sourceLine = sourceLine
        self.label = label
    }
}

/// A candidate that lost the ranking, kept so callers can re-rank.
///
/// Receipts are messy: when the top guess is wrong the right answer is often
/// second, so `Receipt.orderNumberCandidates` exposes all of them.
public struct ReceiptCandidate: Equatable {
    public let value: String
    public let confidence: Double
    public let label: String
    public let sourceLine: String

    public init(value: String, confidence: Double, label: String, sourceLine: String) {
        self.value = value
        self.confidence = confidence
        self.label = label
        self.sourceLine = sourceLine
    }
}
