# Getting started

Everything here runs on a Mac. The package has no dependencies and no build
scripts, so there is nothing to install beyond a Swift toolchain.

## What you need

| | |
| --- | --- |
| macOS | 13 Ventura or later |
| Swift | 5.9 or later. `xcode-select --install` is enough for the inspector. |
| Xcode | Only needed to build an iOS app. Get it from the App Store. |

Check the toolchain first:

```bash
swift --version
```

If that fails, install the command line tools:

```bash
xcode-select --install
```

## Get the code

The repository is private, so cloning needs credentials. Pick whichever suits.

**GitHub CLI** — least fiddly, because it handles authentication for you:

```bash
brew install gh          # if it is not already installed
gh auth login
gh repo clone neonblue227/bake-app-ocr
cd bake-app-ocr
```

**Plain git with a token:**

```bash
mkdir -p ~/Developer && cd ~/Developer
git clone https://github.com/neonblue227/bake-app-ocr.git
cd bake-app-ocr
```

It prompts for a username and password. The password must be a **personal access
token**, not your account password — GitHub → *Settings → Developer settings →
Personal access tokens*, scoped to `bake-app-ocr` with `Contents: Read`.

**SSH**, if the Mac already has a key registered:

```bash
git clone git@github.com:neonblue227/bake-app-ocr.git
```

## Verify it works

```bash
swift test
```

Expect to see:

```
Executed 34 tests, with 0 failures
```

That runs the whole parser against synthetic receipts. No camera, no simulator,
no app. If it is green, parsing works and anything that goes wrong later is a
camera or integration problem, not a parsing one.

## Look at a real receipt

```bash
swift run ReceiptInspector
```

The first build takes about a minute. An inspector window opens — drop a receipt
photo into it, or switch to **Pasted text** and paste receipt text, which skips
OCR entirely and tests the parser directly.

You get the order number with its confidence, every item, the totals, any
warnings, and the raw OCR lines, all side by side, so you can see exactly why a
result came out the way it did.

The same tool runs without a window:

```bash
swift run ReceiptInspector ~/Desktop/receipt.jpg           # summary
swift run ReceiptInspector --json ~/Desktop/receipt.jpg    # JSON
swift run ReceiptInspector --lines receipt.txt             # skip OCR
```

## Try the camera

`Examples/ReceiptScannerDemo` is a small iOS app that exercises all three entry
points: the still camera, the live scanner, and a photo from the library.

```bash
open Examples/ReceiptScannerDemo/ReceiptScannerDemo.xcodeproj
```

Choose a device and run. It needs a real device for the camera — the Simulator
has none — but **Choose from Photos** works there, so you can still check the
parsing without one. The project already has a development team set, so signing
may just work; otherwise pick your own under *Signing & Capabilities*.

Every scan prints the raw OCR lines to the Xcode console, which is the quickest
way to see what Vision actually read before the parser touched it.

The demo targets iOS 17. The package itself is iOS 16, but Thai recognition
needs iOS 17, and the demo is set up to exercise that. Which languages are
requested is configurable:

```swift
ReceiptOCR.Configuration(recognitionLanguages: ["en-US"])
```

## Add it to an iOS app

1. In Xcode, **File → Add Package Dependencies…** and enter
   `git@github.com:neonblue227/bake-app-ocr.git` (SSH) or the HTTPS URL. Add the
   `BakeAppOCR` library to your app target.

2. Add the camera permission to `Info.plist`. Without it the camera view shows
   nothing and iOS logs a crash-on-access:

   ```xml
   <key>NSCameraUsageDescription</key>
   <string>Bake uses the camera to read your receipt.</string>
   ```

3. Show the camera. `ReceiptCameraView` frames the receipt, lets the user tap
   the shutter, and hands you a parsed `Receipt`:

   ```swift
   import BakeAppOCR
   import SwiftUI

   struct ScanScreen: View {
       @State private var isScanning = false
       @State private var receipt: Receipt?

       var body: some View {
           Button("Scan receipt") { isScanning = true }
               .fullScreenCover(isPresented: $isScanning) {
                   ReceiptCameraView { parsed in
                       receipt = parsed
                       isScanning = false
                   }
               }
       }
   }
   ```

4. **To test in the Simulator**, use a photo instead of the camera — the
   Simulator has no camera at all:

   ```swift
   PhotosPicker("Choose a receipt photo", selection: $picked, matching: .images)
       .onChange(of: picked) { _, item in
           Task {
               guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
               receipt = try? ReceiptOCR().scan(imageData: data)
           }
       }
   ```

   `PhotosPicker` needs no permission, because iOS hands your app just the one
   image the user chose.

## The loop that matters

Steps above are one time. After that it is:

```bash
git pull && swift run ReceiptInspector
```

Try real receipts. When one reads wrong, press **Copy summary** in the inspector
and send that over. It includes the raw OCR lines, which is enough to tell
whether the problem is the camera or a parsing rule — and it means the fix gets
made against your actual receipt rather than a guess.

Per-receipt tuning almost always happens in one file:

```
Sources/BakeAppOCR/Parsing/Patterns.swift
```

That is where the order-number labels, the value stoppers and the decoy list
live.

## Troubleshooting

**`swift: command not found`**
Install the toolchain: `xcode-select --install`.

**`could not read Username for 'https://github.com'`**
The clone needs a token, not your account password. Run `gh auth login`, or see
*Get the code* above. Note that fine-grained tokens expire.

**Xcode cannot resolve the package**
Xcode needs its own GitHub credentials. Add them in
*Xcode → Settings → Accounts*, or switch the package URL to the SSH form and make
sure the Mac's key is registered with GitHub.

**The camera shows nothing**
`NSCameraUsageDescription` is missing from `Info.plist`, or the user declined
access. `ReceiptCameraSession.state` reports `.denied` in that case.

**"Live scanning is not available on this device"**
Live scanning needs an A12 chip or later and **never** works in the Simulator.
Use `ReceiptCameraView` with a `PhotosPicker` there.

**An order number is not found, or looks wrong**
Check `receipt.orderNumberCandidates` — the right answer is often second, and
each candidate carries its own confidence and the source line it came from. The
*fixed* pattern to look at first is `Patterns.orderNumberLabels`.

**`unsupported platform` or a macOS version error**
The package targets macOS 13 Ventura and iOS 16. Lowering that floor is a
one-line change in `Package.swift`, but Vision's newer behaviours are worth the
floor.
