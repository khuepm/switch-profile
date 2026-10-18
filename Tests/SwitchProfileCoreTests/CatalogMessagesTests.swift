import Foundation
import Testing
@testable import SwitchProfileCore

@Suite struct CatalogMessagesTests {
    static let errors: [LocalStateError] = [
        .notFound("/x/Local State"),
        .unreadable("/x/Local State", "permission denied"),
        .malformed("not JSON"),
        .noProfiles,
    ]

    @Test(arguments: errors)
    func unavailableNamesTheCause(_ error: LocalStateError) {
        let text = CatalogMessages.unavailable(error)
        #expect(text.hasPrefix("Chrome profiles unavailable"))
        switch error {
        case .notFound(let path): #expect(text.contains(path))
        case .unreadable(let path, let reason): #expect(text.contains(path) && text.contains(reason))
        case .malformed(let reason): #expect(text.contains(reason))
        case .noProfiles: #expect(text.contains("no Chrome profiles"))
        }
    }

    @Test func unreadableRemedyForTheAppNamesTheAccessSettings() {
        let text = CatalogMessages.remedy(.unreadable("/x/Local State", "permission denied"), requester: .app)
        for part in ["Privacy & Security", "App Data", "Full Disk Access", "Switch Profile", "Refresh"] {
            #expect(text.contains(part), "\(part)")
        }
    }

    @Test func unreadableRemedyForTheTerminalNamesTheTerminal() {
        let text = CatalogMessages.remedy(.unreadable("/x/Local State", "permission denied"), requester: .terminal)
        for part in ["Privacy & Security", "App Data", "Full Disk Access", "terminal"] {
            #expect(text.contains(part), "\(part)")
        }
    }

    @Test(arguments: errors)
    func neverSaysNoProfileSet(_ error: LocalStateError) {
        for requester in [CatalogMessages.Requester.app, .terminal] {
            #expect(!CatalogMessages.unavailable(error).contains("has no profile set"))
            #expect(!CatalogMessages.remedy(error, requester: requester).contains("has no profile set"))
        }
    }
}
