import Foundation
import XCTest

/// Loads the receipt fixtures shipped with the test bundle.
enum FixtureLoader {

    static func lines(
        _ name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [String] {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: "txt",
            subdirectory: "Fixtures"
        ) else {
            throw XCTSkip("Fixture \(name).txt is missing from the test bundle", file: file, line: line)
        }

        let contents = try String(contentsOf: url, encoding: .utf8)
        return contents
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
    }
}
