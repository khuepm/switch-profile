import Foundation

/// The four fixed routing rules, evaluated in declaration order; the first match wins.
public enum RuleID: String, Codable, CaseIterable, Sendable, Comparable {
    /// `git.fis.vn`, any path.
    case r1 = "R1"
    /// `github.com/TruckerPoints/trucker-points` and descendants.
    case r2 = "R2"
    /// Any other `github.com` URL.
    case r3 = "R3"
    /// Fallback for every other accepted http(s) URL.
    case r4 = "R4"

    public static func < (lhs: RuleID, rhs: RuleID) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}
