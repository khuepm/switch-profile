import Foundation
import Testing
@testable import SwitchProfileCore

@Suite struct LocalStateLoaderTests {
    @Test func validFixtureProducesSortedCatalog() throws {
        let catalog = try LocalStateLoader.load(from: Fixture.url("local-state-valid"))
        #expect(catalog.profiles.map(\.directory) == [
            "Default", "Profile 30", "Profile 47", "Profile 5", "Profile 6", "Profile 7", "Profile 8", "Profile 9",
        ])
        #expect(catalog.profile(directory: "Profile 30") == ChromeProfile(directory: "Profile 30", displayName: "khuepm18", email: "khuepm18@example.com"))
        #expect(catalog.profile(directory: "Profile 47") == ChromeProfile(directory: "Profile 47", displayName: "truckerpoints.ai", email: "khue@truckerpoints.ai"))
        #expect(catalog.profile(directory: "Default") == ChromeProfile(directory: "Default", displayName: "Person 1", email: "pmkhue.2013@example.com"))
        #expect(catalog.profile(directory: "Profile 7") == ChromeProfile(directory: "Profile 7", displayName: "bob", email: nil))
        #expect(catalog.profile(directory: "Profile 99") == nil)
    }

    @Test func missingNameFallsBackToDirectoryKey() throws {
        let catalog = Fixture.validCatalog()
        #expect(catalog.profile(directory: "Profile 8")?.displayName == "Profile 8")
    }

    @Test func emptyUserNameIsSignedOut() throws {
        let catalog = Fixture.validCatalog()
        #expect(catalog.profile(directory: "Profile 9")?.email == nil)
        #expect(catalog.profile(directory: "Profile 9")?.displayName == "Signed out")
    }

    @Test func emailIsTrimmedAndEmptyNameFallsBack() throws {
        let json = #"{"profile":{"info_cache":{"Profile 1":{"name":"","user_name":"  a@example.com \n"},"Profile 2":{"user_name":"   "}}}}"#
        let catalog = try LocalStateLoader.parse(Data(json.utf8))
        #expect(catalog.profile(directory: "Profile 1") == ChromeProfile(directory: "Profile 1", displayName: "Profile 1", email: "a@example.com"))
        #expect(catalog.profile(directory: "Profile 2")?.email == nil)
    }

    @Test func truncatedFileIsMalformed() {
        expectMalformed { try LocalStateLoader.load(from: Fixture.url("local-state-malformed")) }
    }

    @Test func missingProfileSectionIsMalformed() {
        expectMalformed { try LocalStateLoader.load(from: Fixture.url("local-state-no-profile")) }
    }

    @Test func wrongInfoCacheTypeIsMalformed() {
        expectMalformed { try LocalStateLoader.parse(Data(#"{"profile":{"info_cache":[]}}"#.utf8)) }
    }

    @Test func emptyInfoCacheIsNoProfiles() {
        #expect(throws: LocalStateError.noProfiles) {
            try LocalStateLoader.load(from: Fixture.url("local-state-empty-cache"))
        }
    }

    @Test func invalidKeysAreSkipped() throws {
        let catalog = try LocalStateLoader.load(from: Fixture.url("local-state-bad-key"))
        #expect(catalog.profiles.map(\.directory) == ["Profile 1"])
    }

    @Test func onlyInvalidKeysIsNoProfiles() {
        #expect(throws: LocalStateError.noProfiles) {
            try LocalStateLoader.parse(Data(#"{"profile":{"info_cache":{"..":{},"-x":{}}}}"#.utf8))
        }
    }

    @Test(arguments: ["Default", "Profile 1", "Profile 30", "System Profile", "a.b_c-d", String(repeating: "a", count: 255)])
    func validDirectoryKeys(_ key: String) {
        #expect(LocalStateLoader.isValidDirectoryKey(key))
    }

    @Test(arguments: ["", ".", "..", "-x", "--profile-directory=x", "../x", "a/b", "a\\b", "Profile\n1", "Prøfile",
                      String(repeating: "a", count: 256)])
    func invalidDirectoryKeys(_ key: String) {
        #expect(!LocalStateLoader.isValidDirectoryKey(key))
    }

    @Test func nonexistentPathIsNotFound() {
        let url = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/Local State")
        #expect(throws: LocalStateError.notFound(url.path)) {
            try LocalStateLoader.load(from: url)
        }
    }

    @Test func unreadableFileIsUnreadable() throws {
        let dir = TempDir()
        defer { dir.cleanup() }
        let file = dir.url.appendingPathComponent("Local State")
        try Fixture.data("local-state-valid").write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)

        do {
            _ = try LocalStateLoader.load(from: file)
            Issue.record("expected .unreadable")
        } catch {
            guard case .unreadable(let path, let message) = error else {
                Issue.record("expected .unreadable, got \(error)")
                return
            }
            #expect(path == file.path)
            #expect(!message.isEmpty)
        }
    }

    private func expectMalformed(_ body: () throws -> ProfileCatalog,
                                 sourceLocation: SourceLocation = #_sourceLocation) {
        do {
            _ = try body()
            Issue.record("expected .malformed", sourceLocation: sourceLocation)
        } catch {
            guard case .malformed(let summary)? = error as? LocalStateError else {
                Issue.record("expected .malformed, got \(error)", sourceLocation: sourceLocation)
                return
            }
            #expect(!summary.isEmpty, sourceLocation: sourceLocation)
        }
    }
}
