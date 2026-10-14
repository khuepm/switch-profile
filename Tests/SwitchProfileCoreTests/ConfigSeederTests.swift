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
        #expect(seeded.targets.R1.binding == ProfileBinding(directory: "Profile 30", email: "khuepm18@example.com", displayName: "khuepm18", matchedBy: .displayName))
        #expect(seeded.targets.R2.binding == ProfileBinding(directory: "Profile 47", email: "khue@truckerpoints.ai", displayName: "truckerpoints.ai", matchedBy: .email))
        #expect(seeded.targets.R3.binding == ProfileBinding(directory: "Default", email: "pmkhue.2013@example.com", displayName: "Person 1", matchedBy: .localPart))
        #expect(seeded.targets.R4.binding == nil)
        #expect(seeded.seedPending == false)
        // Identities are kept.
        #expect(seeded.targets.R1.identity == "khuepm18")
    }

    @Test func ambiguousAndNotFoundStayNil() {
        var config = AppConfig.unseededDefault
        config.targets.R1.identity = "dup@example.com"
        config.targets.R2.identity = "nobody"
        config.targets.R3.identity = nil
        let seeded = ConfigSeeder.seed(config, catalog: catalog)
        #expect(seeded.targets.R1.binding == nil)
        #expect(seeded.targets.R2.binding == nil)
        #expect(seeded.targets.R3.binding == nil)
        #expect(seeded.seedPending == false)
    }

    @Test func fallbackIsNeverSeeded() {
        var config = AppConfig.unseededDefault
        config.targets.R4.identity = "khuepm18"
        #expect(ConfigSeeder.seed(config, catalog: catalog).targets.R4.binding == nil)
    }

    @Test func existingBindingIsPreserved() {
        var config = AppConfig.unseededDefault
        let userChoice = ProfileBinding(profile: profile("Profile 9"), matchedBy: nil)
        config.targets.R1.binding = userChoice
        let seeded = ConfigSeeder.seed(config, catalog: catalog)
        #expect(seeded.targets.R1.binding == userChoice)
        #expect(seeded.targets.R2.binding?.directory == "Profile 47")
        #expect(seeded.targets.R3.binding?.directory == "Default")
    }

    @Test func seedPendingClearedWhenNothingMatched() {
        let catalog = ProfileCatalog(profiles: [ChromeProfile(directory: "Profile 1", displayName: "unrelated", email: nil)])
        let seeded = ConfigSeeder.seed(.unseededDefault, catalog: catalog)
        #expect(seeded.seedPending == false)
        #expect(RuleID.allCases.allSatisfy { seeded.targets[$0].binding == nil })
    }

    @Test func otherFieldsUntouched() {
        var config = AppConfig.unseededDefault
        config.previousDefaultBrowser = DefaultBrowserRecord(bundleIdentifier: "com.apple.Safari", path: "/Applications/Safari.app")
        let seeded = ConfigSeeder.seed(config, catalog: catalog)
        #expect(seeded.previousDefaultBrowser == config.previousDefaultBrowser)
        #expect(seeded.schemaVersion == 1)
    }
}
