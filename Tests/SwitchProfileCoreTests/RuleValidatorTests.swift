import Foundation
import Testing
@testable import SwitchProfileCore

/// #14: rule drafts are validated before they are saved; errors are tagged with their field.
@Suite struct RuleValidatorTests {
    static let defaults = AppConfig.unseededDefault.rules

    static func host(_ host: String) -> RuleValidation {
        RuleValidator.validate(RuleDraft(matchType: .host, host: host), existing: [], editing: nil)
    }

    static func prefix(_ host: String, _ path: String, existing: [RoutingRule] = [], editing: RuleID? = nil) -> RuleValidation {
        RuleValidator.validate(RuleDraft(matchType: .hostPathPrefix, host: host, pathPrefix: path),
                               existing: existing, editing: editing)
    }

    static let hostErrors: [(String, RuleFieldError)] = [
        ("", .emptyHost),
        ("   ", .emptyHost),
        ("*.github.com", .wildcardHost),
        ("git*hub.com", .wildcardHost),
        ("https://github.com", .invalidHost),
        ("github.com/x", .invalidHost),
        ("github.com:443", .invalidHost),
        ("user@github.com", .invalidHost),
        ("git hub.com", .invalidHost),
        ("a..b", .invalidHost),
        (".github.com", .invalidHost),
        ("github.com?x", .invalidHost),
        ("github.com#x", .invalidHost),
        ("[::1]", .invalidHost),
        (".", .invalidHost),
        (String(repeating: "a", count: 64) + ".com", .invalidHost),
        (Array(repeating: String(repeating: "a", count: 60), count: 5).joined(separator: "."), .invalidHost),
    ]

    @Test(arguments: hostErrors)
    func invalidHost(_ host: String, _ error: RuleFieldError) {
        let validation = Self.host(host)
        #expect(validation.errors == [error])
        #expect(validation.match == nil)
        #expect(validation.errors(for: .host) == [error])
    }

    static let pathErrors: [(String, RuleFieldError)] = [
        ("", .emptyPath),
        ("  ", .emptyPath),
        ("TruckerPoints/x", .pathMissingLeadingSlash),
        ("/", .pathIsRoot),
        ("/a?b", .invalidPath),
        ("/a#b", .invalidPath),
        ("/a//b", .invalidPath),
        ("//a", .invalidPath),
        ("/a/../b", .invalidPath),
        ("/a/./b", .invalidPath),
        ("/a b", .invalidPath),
        ("/a/%zz", .invalidPath),
        ("/a//", .invalidPath),
    ]

    @Test(arguments: pathErrors)
    func invalidPath(_ path: String, _ error: RuleFieldError) {
        let validation = Self.prefix("github.com", path)
        #expect(validation.errors == [error])
        #expect(validation.errors(for: .path) == [error])
        #expect(validation.match == nil)
    }

    @Test func pathIsIgnoredForExactHost() {
        let validation = RuleValidator.validate(RuleDraft(matchType: .host, host: "github.com", pathPrefix: "no slash"),
                                                existing: [], editing: nil)
        #expect(validation.match == .host("github.com"))
    }

    @Test func normalization() {
        #expect(Self.host("GitHub.com.").match == .host("github.com"))
        #expect(Self.host("  example.org \n").match == .host("example.org"))
        #expect(Self.prefix("GitHub.com", "/Acme/App/").match == .hostPathPrefix(host: "github.com", pathPrefix: "/Acme/App"))
        #expect(Self.prefix("github.com", " /acme ").match == .hostPathPrefix(host: "github.com", pathPrefix: "/acme"))
    }

    @Test(arguments: ["140.82.112.3", "localhost", "git.fis.vn", "a-b.example"])
    func validHosts(_ host: String) {
        #expect(Self.host(host).isValid)
        #expect(Self.host(host).match == .host(host))
    }

    /// Hosts are stored in the form Foundation gives the classifier, so punycode and Unicode entry
    /// both match links to that host.
    @Test func idnHostsAreStoredAsTheClassifierSeesThem() throws {
        let punycode = try #require(Self.host("xn--gthub-cta.com").match)
        #expect(punycode == Self.host("gïthub.com").match)
        let rules = [RoutingRule(id: RuleID(number: 5), match: punycode)]
        for string in ["https://xn--gthub-cta.com/x", "https://gïthub.com/x"] {
            #expect(URLClassifier.classify(URL(string: string)!, rules: rules)
                == .matched(RuleID(number: 5), explanation: punycode.summary))
        }
    }

    @Test func multipleErrorsAreReportedTogether() {
        let validation = Self.prefix("", "no-slash")
        #expect(validation.errors == [.emptyHost, .pathMissingLeadingSlash])
        #expect(validation.errors(for: .host) == [.emptyHost])
        #expect(validation.errors(for: .path) == [.pathMissingLeadingSlash])
    }

    // MARK: Duplicates

    @Test func duplicateOfAnExistingRule() {
        let r1 = RuleValidator.validate(RuleDraft(matchType: .host, host: "GIT.FIS.VN"), existing: Self.defaults, editing: nil)
        #expect(r1.errors == [.duplicate(of: .r1)])
        #expect(r1.errors(for: .rule) == [.duplicate(of: .r1)])
        #expect(Self.prefix("github.com", "/truckerpoints/TRUCKER-POINTS/", existing: Self.defaults).errors == [.duplicate(of: .r2)])
        #expect(Self.prefix("github.com", "/%54ruckerPoints/trucker-points", existing: Self.defaults).errors == [.duplicate(of: .r2)])
    }

    @Test func exactHostAndPrefixOnTheSameHostAreNotDuplicates() {
        #expect(Self.prefix("git.fis.vn", "/fis-gs", existing: Self.defaults).isValid)
        #expect(RuleValidator.validate(RuleDraft(matchType: .host, host: "github.com"),
                                       existing: [Self.defaults[1]], editing: nil).isValid)
        #expect(Self.prefix("github.com", "/TruckerPoints", existing: Self.defaults).isValid)
    }

    @Test func editingARuleToItsOwnValueIsNotADuplicate() {
        #expect(Self.prefix("github.com", "/TruckerPoints/trucker-points", existing: Self.defaults, editing: .r2).isValid)
        #expect(Self.prefix("github.com", "/TruckerPoints/trucker-points", existing: Self.defaults, editing: .r3).errors
            == [.duplicate(of: .r2)])
    }
}
