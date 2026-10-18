import Foundation

/// Identifies one routing rule as `R<n>` (n ≥ 1). The order of evaluation comes from the
/// configuration's rule list, not from the id. `R1`–`R3` are the built-in default rules, `R4` is
/// always the fallback, and rules added in Settings get `R5`, `R6`, … (ids are never reused).
public struct RuleID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    /// nil unless `rawValue` matches `^R[1-9][0-9]*$`.
    public init?(rawValue: String) {
        guard Self.isValid(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    /// `R<number>`; `number` must be at least 1.
    public init(number: Int) {
        precondition(number >= 1, "rule numbers start at 1")
        rawValue = "R\(number)"
    }

    /// The `n` of `R<n>`.
    public var number: Int {
        Int(rawValue.dropFirst()) ?? 0
    }

    /// Default rule: `git.fis.vn`, any path.
    public static let r1 = RuleID(number: 1)
    /// Default rule: `github.com/TruckerPoints/trucker-points` and descendants.
    public static let r2 = RuleID(number: 2)
    /// Default rule: any other `github.com` URL.
    public static let r3 = RuleID(number: 3)
    /// The fallback for every other accepted http(s) URL.
    public static let r4 = RuleID(number: 4)
    /// Always last; cannot be edited, moved or deleted.
    public static let fallback = r4

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard Self.isValid(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "invalid rule id '\(raw)'")
        }
        rawValue = raw
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private static func isValid(_ raw: String) -> Bool {
        let digits = raw.utf8.dropFirst()
        guard raw.utf8.first == UInt8(ascii: "R"), let first = digits.first, first != UInt8(ascii: "0"),
              digits.count <= 9 else { return false }
        return digits.allSatisfy { $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") }
    }
}

extension RuleID: CustomStringConvertible {
    public var description: String { rawValue }
}
