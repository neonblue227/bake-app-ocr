import XCTest

@testable import BakeAppOCR

final class ItemExtractionTests: XCTestCase {

    func testExtractsItemsWithQuantitiesAndPrices() throws {
        let receipt = ReceiptParser().parse(lines: try FixtureLoader.lines("cafe-order"))

        XCTAssertEqual(
            receipt.items.map(\.name),
            ["SOURDOUGH LOAF", "CROISSANT", "FLAT WHITE", "ALMOND TART"]
        )
        XCTAssertEqual(receipt.items[1].quantity, 2)
        XCTAssertEqual(receipt.items[1].unitPrice, Decimal(string: "3.25"))
        XCTAssertEqual(receipt.items[1].lineTotal, Decimal(string: "6.50"))
    }

    func testAdoptsTheDescriptionPrintedBelowThePriceLine() throws {
        let receipt = ReceiptParser().parse(lines: try FixtureLoader.lines("name-after-code"))

        // `FG-A00019 1 1.50 1.50 SR` is a bare code; the name sits underneath.
        XCTAssertEqual(receipt.items.map(\.name), ["GREEN TEA", "KAKE UDON R"])
    }

    func testAdoptsTheDescriptionPrintedAboveThePriceLine() throws {
        let receipt = ReceiptParser().parse(lines: try FixtureLoader.lines("fastfood-order"))

        XCTAssertEqual(receipt.items.first?.name, "CHICMCMUFFIN")
        XCTAssertEqual(receipt.items.first?.quantity, 2)
    }

    func testKeepsAnItemThatHasNoPrice() throws {
        let receipt = ReceiptParser().parse(lines: try FixtureLoader.lines("fastfood-order"))

        XCTAssertEqual(receipt.items.count, 4)
        XCTAssertEqual(receipt.items.last?.name, "L COKE")
        XCTAssertNil(receipt.items.last?.lineTotal)
    }

    func testInfersUnitPriceWhenOnlyALineTotalIsPrinted() throws {
        let receipt = ReceiptParser().parse(lines: try FixtureLoader.lines("fastfood-order"))

        // `2 CHICMCMUFFIN 11.00` implies 5.50 each.
        XCTAssertEqual(receipt.items.first?.unitPrice, Decimal(string: "5.50"))
    }

    func testReadsQuantityFromAnExplicitMultiplier() {
        let receipt = ReceiptParser().parse(lines: [
            "SUPPLY CO",
            "ITEM QTY U.PRICE AMOUNT",
            "9555221301081 4 X 2.80 11.20",
            "TOTAL 11.20",
        ])

        XCTAssertEqual(receipt.items.first?.quantity, 4)
        XCTAssertEqual(receipt.items.first?.unitPrice, Decimal(string: "2.80"))
        XCTAssertEqual(receipt.items.first?.lineTotal, Decimal(string: "11.20"))
    }

    func testStripsTrailingTaxCodesFromNames() {
        let receipt = ReceiptParser().parse(lines: [
            "SUPPLY CO",
            "ITEM QTY U.PRICE AMOUNT TAX",
            "E8318 1 80.91 80.91 SR",
            "TOTAL 80.91",
        ])

        XCTAssertEqual(receipt.items.first?.name, "")
        XCTAssertEqual(receipt.items.first?.lineTotal, Decimal(string: "80.91"))
    }

    func testDoesNotTreatAMeasurementInsideADescriptionAsAPrice() {
        let receipt = ReceiptParser().parse(lines: [
            "HARDWARE CO",
            "ITEM QTY PRICE AMOUNT",
            "TRAILING SKT 5GN+SP 3X1.25MM CABLE 2 *S",
            "SUBTOTAL 0.00",
            "TOTAL 0.00",
        ])

        // `1.25MM` is a cable size. Prices are right-aligned, so text after the
        // number means it was never a price.
        XCTAssertEqual(receipt.items.count, 1)
        XCTAssertNil(receipt.items.first?.lineTotal)
    }

    func testParsesCommaDecimalSeparators() {
        let receipt = ReceiptParser().parse(lines: [
            "BOULANGERIE",
            "ITEM QTY PRIX MONTANT",
            "BAGUETTE 1 1,20 1,20",
            "TOTAL 1,20",
        ])

        XCTAssertEqual(receipt.items.first?.name, "BAGUETTE")
        XCTAssertEqual(receipt.items.first?.lineTotal, Decimal(string: "1.20"))
    }

    func testFlagsWhenItemTotalsDisagreeWithTheReceipt() {
        let receipt = ReceiptParser().parse(lines: [
            "CAFE",
            "ITEM QTY PRICE AMOUNT",
            "TOAST 1 3.00 3.00",
            "SUBTOTAL 9.99",
            "TOTAL 9.99",
        ])

        let hasMismatch = receipt.warnings.contains {
            if case .itemTotalMismatch = $0 { return true }
            return false
        }
        XCTAssertTrue(hasMismatch)
    }
}
