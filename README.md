# BakeAppOCR

On-device receipt OCR for the Bake app. Point it at a photo of a receipt and it
gives you back the **order number** and the **line items**.

Built on Apple's Vision framework. No network calls, no third-party
dependencies, no state between calls.

```swift
import BakeAppOCR

let receipt = try ReceiptOCR().scan(image: cgImage)

receipt.orderNumber?.value        // "10432"
receipt.orderNumber?.confidence   // 0.9 — threshold on this before trusting it
receipt.orderNumberCandidates     // every reading, best first

receipt.items.map(\.name)         // ["SOURDOUGH LOAF", "CROISSANT", ...]
receipt.items[0].quantity         // 1
receipt.items[1].unitPrice        // 3.25

receipt.subtotal, receipt.tax, receipt.total
receipt.warnings                  // what the parser was unsure about
```

## Try it

New to the project? **[GETTING_STARTED.md](GETTING_STARTED.md)** covers cloning,
verifying and running everything below.

```bash
swift run ReceiptInspector
```

That opens an inspector window. Drop in a receipt photo, or switch to
**Pasted text** and paste the receipt text, which skips OCR and tests the parser
directly. Either way you get the order number with its confidence, every item,
the totals, any warnings, and the raw OCR lines side by side, so you can see
exactly why a result came out the way it did.

There is a **Copy summary** button that puts the parsed result *and* the raw OCR
lines on your clipboard — that is what to send when something reads wrong.

The same tool runs headless, which is handy on a machine without a GUI:

```bash
swift run ReceiptInspector ~/Desktop/receipt.jpg           # summary
swift run ReceiptInspector --json ~/Desktop/receipt.jpg    # JSON
swift run ReceiptInspector --lines receipt.txt             # skip OCR entirely
```

## Install

The package has no dependencies, so you can either add it as a package
dependency or drag `Sources/BakeAppOCR` straight into your Xcode project.

Add to `Package.swift`:

```swift
.package(url: "https://github.com/neonblue227/bake-app-ocr.git", from: "1.0.0")
```

Platforms: iOS 16+, macOS 13+. The Vision and parsing layers use nothing newer
than Vision itself, so lowering the floor is a one-line change in
`Package.swift` if you need to.

## Camera

Two ready-made SwiftUI views. Both are iOS-only and both need
`NSCameraUsageDescription` in your `Info.plist`.

### Still capture — best accuracy

```swift
.fullScreenCover(isPresented: $isScanning) {
    ReceiptCameraView { receipt in
        self.receipt = receipt
        isScanning = false
    }
}
```

Live preview, a shutter, and a torch toggle — dim light is the most common
reason a receipt will not read. The captured frame goes through Vision's
accurate pass, which reads a dense receipt far better than live frame analysis
does.

### Live scanning — for long receipts

```swift
LiveReceiptScannerView { receipt in
    self.receipt = receipt
}
```

Text is collected continuously as the user pans down the receipt, then parsed
when they tap Done. Use this when the receipt is taller than the frame, since a
single still only sees what is in view. Lines are ordered by when they were
first recognised, so reading order holds as long as the user starts at the top.

Live scanning is built on VisionKit's `DataScannerViewController`, which needs an
A12 chip or later and **does not run in the Simulator** — use
`ReceiptCameraView` with a `PhotosPicker` there.

### Rolling your own camera UI

```swift
@StateObject private var camera = ReceiptCameraSession()

await camera.start()                                  // skips asking twice
let image = try await camera.capturePhoto()           // -> CGImage
camera.setTorch(true)
```

`ReceiptCameraSession` publishes `state`, `isCapturing` and `isTorchOn` so you
can drive your own controls, and exposes `session` for the preview layer.

## How it works

Three layers, each independently testable:

```
CGImage ──▶ VisionTextRecognizer ──▶ [RecognizedWord]   text + bounding boxes
                                          │
                                          ▼
                                    LineAssembler       words -> visual lines
                                          │
                                          ▼
                                    ReceiptParser       lines -> Receipt
                                          ├── OrderNumberExtractor
                                          ├── ItemExtractor
                                          └── TotalsParser
```

`ReceiptParser` takes plain strings, which is what makes the whole thing
testable without an image or a device:

```swift
let receipt = ReceiptOCR().scan(lineText: ["ORDER NO. 10432", "TOTAL 29.11"])
```

### The rules that matter

These are not guesses. They come from reading 626 real scanned receipts from the
ICDAR 2019 SROIE dataset, plus the CORD dataset for food receipts.

**Truncate the value at the next field.** This is the single most important
rule, and the one a naive implementation gets wrong. Real receipts pack several
fields onto one line:

| Line on the receipt | Correct value | Naive capture |
| --- | --- | --- |
| `DOC NO CS00031663 DATE 25/12/2018` | `CS00031663` | `CS00031663 DATE 25/12/2018` |
| `RECEIPT NO.:003-1220815 PAX: 1` | `003-1220815` | `003-1220815 PAX: 1` |
| `ORD #50 -REG #19- 18/01/2018` | `50` | `50 -REG #19- 18/01/2018` |
| `ORDER NO. 1000219 11/03/2018 06:20 PM` | `1000219` | the whole tail |

`ValueTruncation` cuts at the next known field label, date or time.

**Some things that look like order numbers are not.** A positive list of labels
(`ORDER`, `ORD`, `INVOICE`, `BILL`, `CHECK`, `RECEIPT`, `DOC`, `CASH BILL`,
`TAX INVOICE`, `TRANS`, `REF`) means `TOKEN NO: 0`, `TABLE : 3` and `PAX(S): 0`
are never considered. Single digits, bare years and clock times are rejected
outright. A short value is only credible behind a strong label — `ORD #50` is a
real McDonald's order number, `REF: 7` usually is not.

**Item names appear on either side of the price.** Both of these are real:

```
2 CHICMCMUFFIN 11.00      <- name before the price
FG-A00019 1 1.50 1.50 SR
GREEN TEA                 <- name after the price
```

`ItemExtractor` merges names from both directions. When a price line's own text
is only a product code — nothing but `FG-A00019` and a quantity — it adopts the
adjacent description line as the name.

**Prices are right-aligned.** `TRAILING SKT 5GN+SP 3X1.25MM CABLE 2 *S` contains
`1.25`, but it is a cable size, not a price. Text following a number means the
number was not a price.

**OCR noise is normal.** Real scans produced `ROUR DING ADJUSTMENT` for
`ROUNDING ADJUSTMENT` and `FLEASE COME AOSIN` for `PLEASE COME AGAIN`. Anchor
keywords are matched fuzzily against a squashed form (`ROUR DING` → `ROURDING`,
one edit from `ROUNDING`). Needles of three characters or fewer must match
exactly, because with one edit allowed `TAX` would match `TAL` — which is inside
the word `TOTAL`.

**Totals are the messiest field.** Handled: dot leaders
(`TOTAL AMT................. 60.31`), values that wrapped to the next line,
negative adjustments, `TOTAL : 106.10 6.37` (net then tax), and `TOTAL QTY: 9`
which is a count rather than a total.

**Results are cross-checked.** The item totals are summed and compared against
the subtotal. A disagreement lands in `receipt.warnings` rather than failing
silently.

## Warnings

```swift
for warning in receipt.warnings {
    print(warning.message)
}
```

| Warning | Meaning |
| --- | --- |
| `.orderNumberNotFound` | No label matched and the heuristic found nothing. |
| `.orderNumberLowConfidence(Double)` | Found heuristically; confirm with the user. |
| `.noItemsFound` | No items in the item block. |
| `.itemTotalMismatch(itemsTotal:receiptTotal:)` | Items do not sum to the receipt's own total. |
| `.missingTotal` / `.missingSubtotal` | The receipt did not state it. |

## Tuning it

Nearly all format-specific knowledge lives in
`Sources/BakeAppOCR/Parsing/Patterns.swift` — the label list, the value
stoppers, the decoys, the tax codes. When Bake meets a receipt it gets wrong, a
new entry in that file is usually the whole fix.

`receipt.rawLines` gives you the OCR text that produced the result, which is
what you want while tuning.

## Limitations

Being explicit about what this does *not* do:

- **Totals are best-effort.** If a receipt restates its total in several ways
  (net, ex-tax, rounded), the parser picks the reading closest to
  `subtotal + tax`. It can still miss a tax value when the label and the number
  are split oddly across lines.
- **English/Latin layouts only**, with decimal-point or decimal-comma money.
  The Vision language list is configurable via
  `ReceiptOCR.Configuration.recognitionLanguages`.
- **The still camera reads only what is framed.** A receipt taller than the view
  needs `LiveReceiptScannerView`, or two captures.
- **Live scanning is order-sensitive.** Lines are ordered by when they were first
  recognised, so panning from the bottom up will scramble them.
- **An item with no description yields an empty name.** That is deliberate —
  it means "the price line had no text", not "the name is blank".
- **Digit-confusion repair is not automatic.** Mapping `O` → `0` inside a value
  would corrupt legitimate alphanumeric IDs (`CS00031663` would become
  `C500031663`), so it is not done.

## Development

```bash
swift build
swift test
```

Tests run against text fixtures in `Tests/BakeAppOCRTests/Fixtures`. They are
synthetic receipts modelled on the structures found in the SROIE and CORD
datasets — no real customer, merchant or staff data is included. `ReceiptParser`
is exercisable directly, so no image or device is needed.

CI runs `swift build` and `swift test` on a `macos-14` runner for every push.
