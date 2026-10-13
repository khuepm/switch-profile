import Foundation
import Testing
@testable import SwitchProfileCore

@Suite struct ProfileResolverTests {
    let catalog = Fixture.validCatalog()

    private func profile(_ directory: String) -> ChromeProfile {
        catalog.profile(directory: directory)!
    }

    @Test func displayNameAndLocalPartIsUniqueByDisplayName() {
        // Profile 30 matches by both name and local part; strongest kind wins.
        #expect(ProfileResolver.resolve(identity: "khuepm18", in: catalog) == .unique(profile("Profile 30"), matchedBy: .displayName))
    }

    @Test func fullEmailIsUniqueByEmail() {
        #expect(ProfileResolver.resolve(identity: "khue@truckerpoints.ai", in: catalog) == .unique(profile("Profile 47"), matchedBy: .email))
    }

    @Test func localPartIsUniqueByLocalPart() {
        #expect(ProfileResolver.resolve(identity: "pmkhue.2013", in: catalog) == .unique(profile("Default"), matchedBy: .localPart))
    }

    @Test func duplicateEmailIsAmbiguousAndSorted() {
        #expect(ProfileResolver.resolve(identity: "dup@example.com", in: catalog) == .ambiguous([profile("Profile 5"), profile("Profile 6")]))
    }

    @Test(arguments: ["nobody", "", "   ", "nobody@example.com", "example.com"])
    func notFound(_ identity: String) {
        #expect(ProfileResolver.resolve(identity: identity, in: catalog) == .notFound)
    }

    @Test(arguments: ["KHUEPM18", "  khuepm18  ", "KhuePM18\n"])
    func caseAndWhitespaceInsensitive(_ identity: String) {
        #expect(ProfileResolver.resolve(identity: identity, in: catalog) == .unique(profile("Profile 30"), matchedBy: .displayName))
    }

    @Test func caseInsensitiveEmail() {
        #expect(ProfileResolver.resolve(identity: "KHUE@TruckerPoints.AI", in: catalog) == .unique(profile("Profile 47"), matchedBy: .email))
    }

    @Test func unionOfNameAndLocalPartAcrossProfilesIsAmbiguous() {
        // "bob" is Profile 7's display name and Profile 8's email local part.
        #expect(ProfileResolver.resolve(identity: "bob", in: catalog) == .ambiguous([profile("Profile 7"), profile("Profile 8")]))
    }

    @Test func identityWithAtNeverMatchesLocalPart() {
        // "khuepm18@" contains "@", so only full-email and display-name matching apply.
        #expect(ProfileResolver.resolve(identity: "khuepm18@", in: catalog) == .notFound)
    }

    @Test func displayNameContainingAtMatchesByDisplayName() {
        let catalog = ProfileCatalog(profiles: [ChromeProfile(directory: "Profile 1", displayName: "me@work", email: nil)])
        #expect(ProfileResolver.resolve(identity: "me@work", in: catalog) == .unique(catalog.profiles[0], matchedBy: .displayName))
    }

    @Test func signedOutProfileNeverMatchesByEmail() {
        #expect(ProfileResolver.resolve(identity: "Signed out", in: catalog) == .unique(profile("Profile 9"), matchedBy: .displayName))
    }
}
