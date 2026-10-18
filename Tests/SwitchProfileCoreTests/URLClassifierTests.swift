// Host-mapping vectors encode macOS 14+ Foundation behavior (URL(string:) IDNA/UTS-46 mapping and
// URLComponents.host decoding); the deployment target is macOS 13, tested on macOS 27 only.
import Foundation
import Testing
@testable import SwitchProfileCore

@Suite struct URLClassifierTests {
    /// The built-in rules; every vector below routes exactly as before #14 made rules editable.
    static let rules = AppConfig.unseededDefault.rules

    static let r1: [String] = [
        "https://git.fis.vn/fis-gs/gs-hn/BTP_CPLQG_S7_2025_PM/plvn-v2-backend/-/merge_requests",
        "https://GIT.FIS.VN/x",
        "https://git.fis.vn:8443/x",
        "https://git.fis.vn./",
    ]

    static let r2: [String] = [
        "https://github.com/TruckerPoints/trucker-points",
        "https://github.com/TruckerPoints/trucker-points/",
        "https://github.com/TruckerPoints/trucker-points/issues",
        "https://github.com/TruckerPoints/trucker-points/pull/1",
        "https://github.com/TruckerPoints/trucker-points/pull/123",
        "https://github.com/TruckerPoints/trucker-points/blob/main/README.md",
        "https://github.com/TruckerPoints/trucker-points?tab=readme",
        "https://github.com/TruckerPoints/trucker-points#readme",
        "https://github.com/TruckerPoints/trucker-points?tab=readme#x",
        "https://github.com/truckerpoints/TRUCKER-POINTS/pull/1",
        "https://GitHub.com/TruckerPoints/trucker-points",
        "https://github.com./TruckerPoints/trucker-points",
        "https://github.com:443/TruckerPoints/trucker-points",
        "https://user@github.com:443/TruckerPoints/trucker-points",
        "https://github.com/%54ruckerPoints/trucker-points",
        "https://github.com/TruckerPoints/trucker-points.git",
        "https://github.com/TruckerPoints/trucker-points.GIT",
        "http://github.com/TruckerPoints/trucker-points",
        "https://github.com/TruckerPoints/trucker-points/pull/1?a=1&b=%20#L10-L20",
    ]

    static let r3: [String] = [
        "https://github.com/TruckerPoints/trucker-points-other",
        "https://github.com/TruckerPoints/trucker-points-other/issues",
        "https://github.com/TruckerPoints/trucker-pointsX",
        "https://github.com/TruckerPoints",
        "https://github.com/TruckerPoints/",
        "https://github.com/khuepm/LumiBase",
        "https://github.com",
        "https://github.com/",
        "https://github.com//TruckerPoints//trucker-points",
        "https://github.com/x/../TruckerPoints/trucker-points",
        "https://github.com/TruckerPoints/trucker-points%2Fx",
        "https://github.com/orgs/TruckerPoints/people",
        "https://github.com/?q=TruckerPoints/trucker-points",
        "HTTPS://github.com/khuepm/LumiBase",
        // Host forms Foundation maps to github.com.
        "https://ｇｉｔｈｕｂ.com/x",
        "https://github%2Ecom/x",
    ]

    static let r4: [String] = [
        "https://github.com.example.org/TruckerPoints/trucker-points",
        "https://notgithub.com/",
        "https://git.fis.vn.example.org/",
        "https://example.com/?u=https://github.com/TruckerPoints/trucker-points",
        "https://example.com/#github.com",
        "https://www.github.com/TruckerPoints/trucker-points",
        "https://api.github.com/repos/x",
        "https://gist.github.com/x",
        "https://raw.githubusercontent.com/x",
        "https://sub.git.fis.vn/",
        "https://[::1]/",
        "https://140.82.112.3/",
        "https://github.com%2Eexample.org/",
        // IDN: classified from the punycoded URL.
        "https://gïthub.com/x",
    ]

    static let unsupportedSchemes: [(String, String)] = [
        ("ftp://github.com/x", "ftp"),
        ("file:///tmp/a.html", "file"),
        ("mailto:a@example.com", "mailto"),
        ("javascript:alert(1)", "javascript"),
        ("chrome://settings", "chrome"),
        ("about:blank", "about"),
        ("FTP://github.com/x", "ftp"),
    ]

    private static func url(_ string: String) -> URL {
        guard let url = URL(string: string) else { fatalError("vector does not parse: \(string)") }
        return url
    }

    private static func rule(of string: String) -> RuleID? {
        if case .matched(let rule, _) = URLClassifier.classify(url(string), rules: Self.rules) { return rule }
        return nil
    }

    @Test(arguments: r1) func matchesR1(_ string: String) {
        #expect(Self.rule(of: string) == .r1)
    }

    @Test(arguments: r2) func matchesR2(_ string: String) {
        #expect(Self.rule(of: string) == .r2)
    }

    @Test(arguments: r3) func matchesR3(_ string: String) {
        #expect(Self.rule(of: string) == .r3)
    }

    @Test(arguments: r4) func matchesR4(_ string: String) {
        #expect(Self.rule(of: string) == .r4)
    }

    @Test(arguments: unsupportedSchemes) func rejectsUnsupportedScheme(_ string: String, _ scheme: String) {
        #expect(URLClassifier.classify(Self.url(string), rules: Self.rules) == .rejected(.unsupportedScheme(scheme)))
    }

    @Test func rejectsMissingHost() {
        #expect(URLClassifier.classify(Self.url("https:///foo"), rules: Self.rules) == .rejected(.malformed(.missingHost)))
    }

    @Test func rejectsMissingScheme() {
        #expect(URLClassifier.classify(Self.url("//github.com/x"), rules: Self.rules) == .rejected(.malformed(.missingScheme)))
    }

    @Test func lengthBoundary() {
        let base = "https://example.com/"
        let atLimit = base + String(repeating: "a", count: URLClassifier.maxURLBytes - base.utf8.count)
        #expect(atLimit.utf8.count == 524_288)
        #expect(URLClassifier.maxURLBytes == 524_288)
        #expect(Self.rule(of: atLimit) == .r4)

        let overLimit = atLimit + "a"
        #expect(overLimit.utf8.count == 524_289)
        #expect(URLClassifier.classify(Self.url(overLimit), rules: Self.rules) == .rejected(.malformed(.tooLong)))
    }

    @Test func explanationNamesHostAndPath() {
        #expect(URLClassifier.classify(Self.url("https://github.com/TruckerPoints/trucker-points"), rules: Self.rules)
            == .matched(.r2, explanation: "host github.com, path /TruckerPoints/trucker-points"))
        #expect(URLClassifier.classify(Self.url("https://git.fis.vn/x"), rules: Self.rules)
            == .matched(.r1, explanation: "host git.fis.vn"))
        #expect(URLClassifier.classify(Self.url("https://example.com/"), rules: Self.rules)
            == .matched(.r4, explanation: "host example.com matches no rule; fallback"))
    }

    @Test func classificationNeverAltersTheURL() {
        for string in Self.r1 + Self.r2 + Self.r3 + Self.r4 {
            let url = Self.url(string)
            let before = url.absoluteString
            _ = URLClassifier.classify(url, rules: Self.rules)
            #expect(url.absoluteString == before)
        }
    }
}
