#if os(macOS)
import SwiftUI

/// The inspector window.
///
/// Entry is via `main.swift`, which routes command-line arguments to
/// ``ReceiptInspectorCLI`` and otherwise calls `main()` on this type.
struct ReceiptInspectorApp: App {
    var body: some Scene {
        WindowGroup("Receipt Inspector") {
            ContentView()
        }
        .defaultSize(width: 1100, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
#endif
