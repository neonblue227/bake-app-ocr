import XCTest

@testable import BakeAppOCR

final class TotalsTests: XCTestCase {

    func testParsesSubtotalTaxAndTotal() throws {
        let receipt = ReceiptParser().parse(lines: try FixtureLoader.lines("cafe-order"))

        XCTAssertEqual(receipt.subtotal, Decimal(string: "26.95"))
        XCTAssertEqual(receipt.tax, Decimal(string: "2.16"))
        XCTAssertEqual(receipt.total, Decimal(string: "29.11"))
    }

    func testHandlesDotLeadersAndNegativeAdjustments() throws {
        let receipt = ReceiptParser().parse(lines: try FixtureLoader.lines("noisy-receipt"))

        XCTAssertEqual(receipt.subtotal, Decimal(string: "13.00"))
        XCTAssertEqual(receipt.tax, Decimal(string: "1.04"))
        XCTAssertEqual(receipt.total, Decimal(string: "14.04"))
    }

    func testRecognisesATotalDespiteOCRSubstitution() {
        // Real scans turn `TOTAL` into `T0TAL`.
        let receipt = ReceiptParser().parse(lines: ["SHOP", "T0TAL 5.00"])

        XCTAssertEqual(receipt.total, Decimal(string: "5.00"))
    }

    func testRecognisesASpacedSubtotal() {
        let receipt = ReceiptParser().parse(lines: ["SHOP", "SUB TOTAL : 4.00", "TOTAL 4.00"])

        XCTAssertEqual(receipt.subtotal, Decimal(string: "4.00"))
    }

    func testIgnoresTotalsThatAreActuallyItemCounts() {
        let receipt = ReceiptParser().parse(lines: [
            "SHOP",
            "TOTAL QTY: 9 327.00",
            "TOTAL 327.00",
        ])

        XCTAssertEqual(receipt.total, Decimal(string: "327.00"))
    }

    func testReadsAValueThatWrappedOntoTheNextLine() {
        let receipt = ReceiptParser().parse(lines: [
            "SHOP",
            "SUBTOTAL 5.00",
            "TOTAL",
            "5.00",
        ])

        XCTAssertEqual(receipt.total, Decimal(string: "5.00"))
    }

    func testPrefersTheTotalClosestToSubtotalPlusTax() {
        let receipt = ReceiptParser().parse(lines: [
            "SHOP",
            "SUBTOTAL 100.00",
            "TAX 8.00",
            "TOTAL EXCLUDED TAX 100.00",
            "TOTAL 108.00",
        ])

        XCTAssertEqual(receipt.total, Decimal(string: "108.00"))
    }

    func testReportsMissingTotals() {
        let receipt = ReceiptParser().parse(lines: ["SHOP", "ITEM QTY PRICE AMOUNT", "TEA 1 2.00 2.00"])

        XCTAssertTrue(receipt.warnings.contains(.missingTotal))
        XCTAssertTrue(receipt.warnings.contains(.missingSubtotal))
    }

    func testDoesNotMistakeARoundingLineForARealTotal() throws {
        let receipt = ReceiptParser().parse(lines: try FixtureLoader.lines("noisy-receipt"))

        XCTAssertFalse(receipt.warnings.contains(.missingTotal))
    }
}
