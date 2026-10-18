import Foundation
import Testing
@testable import SwitchProfileCore

@Suite struct ConfigValidatorTests {
    static let catalog = Fixture.validCatalog()
    static let fis = catalog.profile(directory: "Profile 30")!
    static let tp = catalog.profile(directory: "Profile 47")!
    static let personal = catalog.profile(directory: "Default")!
    static let signedOut = catalog.profile(directory: "Profile 9")!

    static let gone = ProfileBinding(directory: "Profile 99", email: nil, displayName: "Gone", matchedBy: nil)
    static let stale = ProfileBinding(directory: "Profile 47", email: "old@example.com", displayName: "truckerpoints.ai", matchedBy: nil)

    /// R1 confirmed ok, R2 identity mismatch, R3 auto-detected by local part, R4 unset (last active).
    static func mixedConfig() -> AppConfig {
        var config = AppConfig.unseededDefault
        config.seedPending = false
        config.setBinding(ProfileBinding(profile: fis, matchedBy: nil), for: .r1)
        config.setBinding(stale, for: .r2)
        config.setBinding(ProfileBinding(profile: personal, matchedBy: .localPart), for: .r3)
        return config
    }

    @Test func statusCoversEveryCase() {
        var config = Self.mixedConfig()
        config.setBinding(Self.gone, for: .r4)
        let statuses = ConfigValidator.status(config: config, catalog: .loaded(Self.catalog))
        #expect(statuses == [
            .r1: .ok(Self.fis, autoDetected: nil),
            .r2: .identityMismatch(Self.stale, current: Self.tp),
            .r3: .ok(Self.personal, autoDetected: .localPart),
            .r4: .missing(Self.gone),
        ])
    }

    @Test func unsetAndCatalogUnavailable() {
        let statuses = ConfigValidator.status(config: Self.mixedConfig(), catalog: .unavailable(.noProfiles))
        #expect(statuses == [
            .r1: .catalogUnavailable(.noProfiles),
            .r2: .catalogUnavailable(.noProfiles),
            .r3: .catalogUnavailable(.noProfiles),
            .r4: .lastActiveChrome,
        ])
    }

    @Test(arguments: [
        CatalogState.loaded(catalog),
        .loaded(ProfileCatalog(profiles: [fis, signedOut])),
        .loaded(ProfileCatalog(profiles: [ChromeProfile(directory: "Default", displayName: "Person 1", email: "someone@example.com")])),
        .unavailable(.notFound("/x")),
    ], [ProfileBinding?.some(gone), nil])
    func agreesWithRouter(_ catalog: CatalogState, _ fallback: ProfileBinding?) {
        var config = Self.mixedConfig()
        config.setBinding(fallback, for: .r4)
        let urls: [RuleID: URL] = [
            .r1: URL(string: "https://git.fis.vn/x")!,
            .r2: URL(string: "https://github.com/TruckerPoints/trucker-points")!,
            .r3: URL(string: "https://github.com/khuepm/LumiBase")!,
            .r4: URL(string: "https://example.com/")!,
        ]
        let statuses = ConfigValidator.status(config: config, catalog: catalog)
        for rule in config.ruleOrder {
            let decision = Router.decide(urls[rule]!, config: .loaded(config), catalog: catalog)
            switch (statuses[rule]!, decision) {
            case (.ok(let profile, _), .launch(let target, _)):
                #expect(target.directory == profile.directory)
            case (.lastActiveChrome, .launch(let target, _)):
                #expect(target.profile == .lastActiveChrome)
            case (.unset, .needsProfile(_, _, .unset, _)):
                break
            case (.missing(let a), .needsProfile(_, _, .missing(let b), _)):
                #expect(a == b)
            case (.identityMismatch(let a, let pa), .needsProfile(_, _, .identityMismatch(let b, let pb), _)):
                #expect(a == b)
                #expect(pa == pb)
            case (.catalogUnavailable(let a), .needsProfile(_, _, .catalogUnavailable(let b), _)):
                #expect(a == b)
            default:
                Issue.record("\(rule): status \(statuses[rule]!) disagrees with decision \(decision)")
            }
        }
    }

    @Test func confirmedBindingOfAutoDetectedClearsMatchedBy() {
        let seeded = ProfileBinding(profile: Self.personal, matchedBy: .localPart)
        var expected = seeded
        expected.matchedBy = nil
        #expect(ConfigValidator.confirmedBinding(for: .ok(Self.personal, autoDetected: .localPart)) == expected)
    }

    @Test func confirmedBindingOfMismatchUsesCurrentIdentity() {
        let confirmed = ConfigValidator.confirmedBinding(for: .identityMismatch(Self.stale, current: Self.tp))
        #expect(confirmed == ProfileBinding(directory: "Profile 47", email: "khue@truckerpoints.ai", displayName: "truckerpoints.ai", matchedBy: nil))
    }

    @Test(arguments: [
        TargetStatus.unset,
        .lastActiveChrome,
        .missing(gone),
        .catalogUnavailable(.noProfiles),
        .ok(fis, autoDetected: nil),
    ])
    func confirmedBindingNilWhenNothingToConfirm(_ status: TargetStatus) {
        #expect(ConfigValidator.confirmedBinding(for: status) == nil)
    }

    static let order = AppConfig.unseededDefault.ruleOrder

    @Test func needsAttentionCountsOnlyBrokenBindings() {
        #expect(ConfigValidator.needsAttention([
            .r1: .ok(Self.fis, autoDetected: nil), .r2: .unset, .r3: .missing(Self.gone), .r4: .lastActiveChrome,
        ], order: Self.order) == [.r3])
        #expect(ConfigValidator.needsAttention([
            .r1: .identityMismatch(Self.stale, current: Self.tp),
            .r2: .ok(Self.tp, autoDetected: .email),
            .r3: .missing(Self.gone),
            .r4: .ok(Self.signedOut, autoDetected: nil),
        ], order: Self.order) == [.r1, .r3])
        #expect(ConfigValidator.needsAttention([.r1: .unset, .r2: .unset, .r3: .unset, .r4: .unset], order: Self.order) == [])
        #expect(ConfigValidator.needsAttention([.r1: .unset, .r2: .unset, .r3: .unset, .r4: .lastActiveChrome], order: Self.order) == [])
        let unavailable = TargetStatus.catalogUnavailable(.notFound("/x"))
        #expect(ConfigValidator.needsAttention([.r1: unavailable, .r2: unavailable, .r3: unavailable, .r4: unavailable], order: Self.order) == [])
    }

    /// The result follows the configuration's evaluation order, e.g. a user rule above R3.
    @Test func needsAttentionFollowsEvaluationOrder() {
        let order = [RuleID.r1, RuleID(number: 5), .r3, .r2, .fallback]
        let statuses: [RuleID: TargetStatus] = [
            .r1: .unset, RuleID(number: 5): .missing(Self.gone), .r2: .missing(Self.gone),
            .r3: .identityMismatch(Self.stale, current: Self.tp), .r4: .lastActiveChrome,
        ]
        #expect(ConfigValidator.needsAttention(statuses, order: order) == [RuleID(number: 5), .r3, .r2])
    }
}
