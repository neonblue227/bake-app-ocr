import XCTest

@testable import BakeAppOCR

final class OrderNumberTests: XCTestCase {

    func testFindsLabelledOrderNumberAndStopsAtTheTrailingDate() throws {
        let receipt = ReceiptParser().parse(lines: try FixtureLoader.lines("cafe-order"))

        XCTAssertEqual(receipt.orderNumber?.value, "10432")
        XCTAssertEqual(receipt.orderNumber?.label, "ORDER")
        XCTAssertGreaterThan(receipt.orderNumber?.confidence ?? 0, 0.5)
    }

    func testStopsValueAtTheNextFieldBoundary() throws {
        let receipt = ReceiptParser().parse(lines: try FixtureLoader.lines("fastfood-order"))

        // `ORD #50 -REG #19- 18/01/2018 10:27:03` must yield `50`.
        XCTAssertEqual(receipt.orderNumber?.value, "50")
    }

    func testPrefersOrderNumberOverInvoiceNumber() throws {
        let receipt = ReceiptParser().parse(lines: try FixtureLoader.lines("fastfood-order"))

        // The receipt carries both `INV# 003281900229170` and `ORD #50`.
        XCTAssertEqual(receipt.orderNumber?.label, "ORD")
        XCTAssertTrue(receipt.orderNumberCandidates.contains { $0.label == "INVOICE" })
    }

    func testIgnoresTokenAndTableDecoys() throws {
        let receipt = ReceiptParser().parse(lines: try FixtureLoader.lines("decoy-token"))

        XCTAssertEqual(receipt.orderNumber?.value, "55810")

        let values = receipt.orderNumberCandidates.map(\.value)
        XCTAssertFalse(values.contains("0"), "`TOKEN NO: 0` is not an order number")
        XCTAssertFalse(values.contains("3"), "`TABLE : 3` is not an order number")
        XCTAssertFalse(values.contains("DANA"), "the cashier name is not an order number")
    }

    func testNeverReturnsADateAsTheOrderNumber() throws {
        let receipt = ReceiptParser().parse(lines: try FixtureLoader.lines("decoy-token"))

        XCTAssertFalse(
            receipt.orderNumberCandidates.contains { $0.value.contains("2026") },
            "A date must never survive as an order number"
        )
    }

    func testFindsValueWhenLabelSitsAloneOnItsLine() {
        let receipt = ReceiptParser().parse(lines: [
            "THE DAILY CRUMB",
            "ORDER NO:",
            "A-4471",
            "TOTAL 4.00",
        ])

        XCTAssertEqual(receipt.orderNumber?.value, "A-4471")
        XCTAssertTrue(receipt.orderNumber?.label?.contains("next line") ?? false)
    }

    func testDoesNotTreatTheNextLabelledLineAsAValue() {
        let receipt = ReceiptParser().parse(lines: [
            "RECEIPT",
            "INVOICE NO: 99881",
            "TOTAL 4.00",
        ])

        // `RECEIPT` alone, then a line with its own label: nothing to take.
        XCTAssertEqual(receipt.orderNumber?.value, "99881")
        XCTAssertEqual(receipt.orderNumber?.label, "INVOICE")
    }

    func testFallsBackToAnUnlabelledIdentifier() {
        let receipt = ReceiptParser().parse(lines: [
            "QUICK MART",
            "SH01 ZK09 T4 R000027830",
            "TOTAL 5.00",
        ])

        XCTAssertEqual(receipt.orderNumber?.value, "R000027830")
        XCTAssertEqual(receipt.orderNumber?.confidence ?? 1, OrderNumberExtractor.heuristicConfidence, accuracy: 0.0001)
    }

    func testMissingOrderNumberIsReportedAsAWarning() {
        let receipt = ReceiptParser().parse(lines: ["JUST A NOTE", "TOTAL 1.00"])

        XCTAssertNil(receipt.orderNumber)
        XCTAssertTrue(receipt.warnings.contains(.orderNumberNotFound))
    }
}
