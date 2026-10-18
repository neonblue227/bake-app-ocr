import Foundation

// The graphical inspector is macOS-only. On any other platform this executable
// still compiles; it just has no window to show.
#if os(macOS)
if CommandLine.arguments.count > 1 {
    exit(ReceiptInspectorCLI.run(arguments: Array(CommandLine.arguments.dropFirst())))
}
ReceiptInspectorApp.main()
#else
exit(1)
#endif
