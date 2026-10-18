import Foundation
import Testing
@testable import SwitchProfileCore

@Suite struct ConfigSeederTests {
    let catalog = Fixture.validCatalog()

    private func profile(_ directory: String) -> ChromeProfile {
        catalog.profile(directory: directory)!
    }

    @Test func uniqueIdentitiesBecomeAutoDetectedBindings() {
        let seeded = ConfigSeeder.seed(.unseededDefault, catalog: catalog)
        #expect(seeded.binding(for: .r1) == ProfileBinding(directory: "Profile 30", email: "khuepm18@example.com", displayName: "khuepm18", matchedBy: .displayName))
        #expect(seeded.binding(for: .r2) == ProfileBinding(directory: "Profile 47", email: "khue@truckerpoints.ai", displayName: "truckerpoints.ai", matchedBy: .email))
        #expect(seeded.binding(for: .r3) == ProfileBinding(directory: "Default", email: "pmkhue.2013@example.com", displayName: "Person 1", matchedBy: .localPart))
        #expect(seeded.binding(for: .r4) == nil)
        #expect(seeded.seedPending == false)
        // Identities are kept.
        #expect(seeded.identity(for: .r1) == "khuepm18")
    }

    @Test func ambiguousAndNotFoundStayNil() {
        var config = AppConfig.unseededDefault
        config.rules[0].identity = "dup@example.com"
        config.rules[1].identity = "nobody"
        config.rules[2].identity = nil
        let seeded = ConfigSeeder.seed(config, catalog: catalog)
        #expect(seeded.binding(for: .r1) == nil)
        #expect(seeded.binding(for: .r2) == nil)
        #expect(seeded.binding(for: .r3) == nil)
        #expect(seeded.seedPending == false)
    }

    @Test func fallbackIsNeverSeeded() {
        var config = AppConfig.unseededDefault
        config.fallback.identity = "khuepm18"
        #expect(ConfigSeeder.seed(config, catalog: catalog).binding(for: .r4) == nil)
    }

    @Test func existingBindingIsPreserved() {
        var config = AppConfig.unseededDefault
        let userChoice = ProfileBinding(profile: profile("Profile 9"), matchedBy: nil)
        config.setBinding(userChoice, for: .r1)
        let seeded = ConfigSeeder.seed(config, catalog: catalog)
        #expect(seeded.binding(for: .r1) == userChoice)
        #expect(seeded.binding(for: .r2)?.directory == "Profile 47")
        #expect(seeded.binding(for: .r3)?.directory == "Default")
    }

    @Test func seedPendingClearedWhenNothingMatched() {
        let catalog = ProfileCatalog(profiles: [ChromeProfile(directory: "Profile 1", displayName: "unrelated", email: nil)])
        let seeded = ConfigSeeder.seed(.unseededDefault, catalog: catalog)
        #expect(seeded.seedPending == false)
        #expect(seeded.ruleOrder.allSatisfy { seeded.binding(for: $0) == nil })
    }

    @Test func otherFieldsUntouched() {
        var config = AppConfig.unseededDefault
        config.previousDefaultBrowser = DefaultBrowserRecord(bundleIdentifier: "com.apple.Safari", path: "/Applications/Safari.app")
        let seeded = ConfigSeeder.seed(config, catalog: catalog)
        #expect(seeded.previousDefaultBrowser == config.previousDefaultBrowser)
        #expect(seeded.schemaVersion == 2)
        #expect(seeded.rules.map(\.match) == config.rules.map(\.match))
        #expect(seeded.nextRuleNumber == config.nextRuleNumber)
    }
}
