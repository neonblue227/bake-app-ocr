import XCTest

@testable import BakeAppOCR

final class LiveTextAccumulatorTests: XCTestCase {

    func testIgnoresRepeatedReadingsOfTheSameLine() {
        var accumulator = LiveTextAccumulator()
        accumulator.add("ORDER NO. 10432")
        accumulator.add("ORDER NO. 10432")
        accumulator.add("order no. 10432")

        XCTAssertEqual(accumulator.lines, ["ORDER NO. 10432"])
    }

    func testPrefersTheLongerOfTwoPrefixReadings() {
        var accumulator = LiveTextAccumulator()
        accumulator.add("GREEN")
        accumulator.add("GREEN TEA")

        XCTAssertEqual(accumulator.lines, ["GREEN TEA"])
    }

    func testKeepsFirstSeenOrder() {
        var accumulator = LiveTextAccumulator()
        accumulator.add("ORDER NO. 10432")
        accumulator.add("ITEM QTY PRICE AMOUNT")
        accumulator.add("SOURDOUGH LOAF 1 6.50 6.50")

        XCTAssertEqual(accumulator.lines, [
            "ORDER NO. 10432",
            "ITEM QTY PRICE AMOUNT",
            "SOURDOUGH LOAF 1 6.50 6.50",
        ])
    }

    func testDropsSingleCharacterNoise() {
        var accumulator = LiveTextAccumulator()
        accumulator.add(".")
        accumulator.add("|")
        accumulator.add("OK")

        XCTAssertEqual(accumulator.lines, ["OK"])
    }

    func testResetClearsEverything() {
        var accumulator = LiveTextAccumulator()
        accumulator.add("ORDER NO. 10432")
        accumulator.reset()

        XCTAssertTrue(accumulator.isEmpty)
        XCTAssertEqual(accumulator.count, 0)
    }

    func testCollectedLinesFeedTheParser() {
        var accumulator = LiveTextAccumulator()
        [
            "THE DAILY CRUMB BAKERY",
            "ORDER NO. 10432 14/03/2026",
            "ITEM QTY PRICE AMOUNT",
            "SOURDOUGH LOAF 1 6.50 6.50",
            "SUBTOTAL 6.50",
            "TOTAL 6.50",
        ].forEach { accumulator.add($0) }

        let receipt = ReceiptOCR().scan(lineText: accumulator.lines)

        XCTAssertEqual(receipt.orderNumber?.value, "10432")
        XCTAssertEqual(receipt.items.first?.name, "SOURDOUGH LOAF")
        XCTAssertEqual(receipt.total, Decimal(string: "6.50"))
    }
}
