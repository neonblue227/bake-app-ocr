import Foundation

/// Collects text reported by a live scanner into a stable, de-duplicated set of lines.
///
/// A live scanner re-reports the same words as the camera moves, and a receipt
/// is usually taller than the frame. Accumulating over time is what lets a user
/// pan down a receipt and still end up with every line.
///
/// Lines keep the order they were first seen, which matches reading order as
/// long as the user works from the top down.
public struct LiveTextAccumulator {

    private struct Entry {
        let key: String
        var text: String
    }

    private var entries: [Entry] = []

    public init() {}

    /// Every distinct line, in the order it was first seen.
    public var lines: [String] { entries.map(\.text) }

    public var isEmpty: Bool { entries.isEmpty }

    public var count: Int { entries.count }

    /// Adds a recognised block. Repeat readings of the same text are ignored.
    ///
    /// Scanners commonly report a prefix first (`GREEN`) and the complete block
    /// a moment later (`GREEN TEA`), so when two readings are prefixes of one
    /// another the longer one wins.
    public mutating func add(_ text: String) {
        let cleaned = TextNormalizer.normalize(text)
        let key = TextNormalizer.squashed(cleaned)

        // One or two characters is almost always scanner noise.
        guard key.count >= 2 else { return }

        if let index = entries.firstIndex(where: { $0.key.hasPrefix(key) || key.hasPrefix($0.key) }) {
            if key.count > entries[index].key.count {
                entries[index] = Entry(key: key, text: cleaned)
            }
            return
        }

        entries.append(Entry(key: key, text: cleaned))
    }

    public mutating func reset() {
        entries.removeAll()
    }
}
