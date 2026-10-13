import Foundation
import Testing
@testable import SwitchProfileCore

/// AC-39 (plan D8): the three READMEs carry the same required sections, each marked with an
/// `<!-- sp:… -->` comment, exactly once and in the same order.
@Suite struct DocsParityTests {
    static let markers = [
        "requirements", "build-install", "configuration", "default-browser", "troubleshooting",
        "restore", "remove", "version", "signing", "known-limitations",
    ].map { "<!-- sp:\($0) -->" }

    static let readmes = ["README.md", "README.vi.md", "README.zh-CN.md"]

    static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // SwitchProfileCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // package root

    static func text(of readme: String) throws -> String {
        try String(contentsOf: packageRoot.appendingPathComponent(readme), encoding: .utf8)
    }

    /// Every `<!-- sp:… -->` marker in `text`, in document order.
    static func markersInOrder(_ text: String) throws -> [String] {
        let regex = try NSRegularExpression(pattern: "<!-- sp:[a-z-]+ -->")
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    @Test(arguments: readmes)
    func readmeHasEveryMarkerOnceInOrder(_ readme: String) throws {
        let found = try Self.markersInOrder(Self.text(of: readme))
        #expect(found == Self.markers)
    }

    @Test func readmesShareTheSameMarkerSequence() throws {
        let sequences = try Self.readmes.map { try Self.markersInOrder(Self.text(of: $0)) }
        #expect(Set(sequences.map { $0.joined(separator: "\n") }).count == 1)
    }

    @Test func markerCheckDetectsReorderingAndDuplicates() throws {
        let swapped = Self.markers[1] + "\n" + Self.markers[0] + "\n" + Self.markers.dropFirst(2).joined(separator: "\n")
        #expect(try Self.markersInOrder(swapped) != Self.markers)
        let duplicated = (Self.markers + [Self.markers[0]]).joined(separator: "\n")
        #expect(try Self.markersInOrder(duplicated) != Self.markers)
    }
}
