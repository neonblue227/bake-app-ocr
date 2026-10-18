import BakeAppOCR
import Foundation

/// Headless mode, so the tool is useful on a Mac without a window and can be
/// smoke-tested in CI.
///
/// ```bash
/// ReceiptInspector receipt.jpg              # OCR an image and print a summary
/// ReceiptInspector --json receipt.jpg       # ... as JSON
/// ReceiptInspector --lines receipt.txt      # parse text, skipping OCR entirely
/// ```
enum ReceiptInspectorCLI {

    static func run(arguments: [String]) -> Int32 {
        var remaining = arguments
        var asJSON = false
        var parseLines = false
        var path: String?

        while !remaining.isEmpty {
            let argument = remaining.removeFirst()
            switch argument {
            case "--help", "-h":
                printUsage()
                return 0
            case "--json":
                asJSON = true
            case "--lines", "--text":
                parseLines = true
            default:
                guard !argument.hasPrefix("-") else {
                    fail("unknown option '\(argument)'")
                    return 2
                }
                path = argument
            }
        }

        guard let path else {
            printUsage()
            return 2
        }

        let expanded = (path as NSString).expandingTildeInPath
        let receipt: Receipt

        do {
            if parseLines {
                let contents = try String(contentsOf: URL(fileURLWithPath: expanded), encoding: .utf8)
                receipt = ReceiptOCR().scan(lineText: lines(from: contents))
            } else {
                receipt = try ReceiptOCR().scan(imageAt: URL(fileURLWithPath: expanded))
            }
        } catch {
            fail("\(error)")
            return 1
        }

        print(asJSON ? ReceiptSummary.json(for: receipt) : ReceiptSummary.text(for: receipt, includeRawLines: parseLines))
        return 0
    }

    private static func lines(from contents: String) -> [String] {
        contents
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    private static func fail(_ message: String) {
        FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    }

    private static func printUsage() {
        print("""
        ReceiptInspector - see what BakeAppOCR reads from a receipt

        USAGE
          ReceiptInspector [options] <file>

        OPTIONS
          --lines     Treat the file as receipt text, one OCR line per row,
                      and skip OCR entirely.
          --json      Print JSON instead of a summary.
          -h, --help  Show this message.

        EXAMPLES
          ReceiptInspector ~/Desktop/receipt.jpg
          ReceiptInspector --json ~/Desktop/receipt.jpg
          ReceiptInspector --lines Tests/BakeAppOCRTests/Fixtures/cafe-order.txt

        Run with no arguments to open the graphical inspector.
        """)
    }
}
