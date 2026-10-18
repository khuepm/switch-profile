import AppKit
import Testing
@testable import SwitchProfileUI

/// The agent app has no AppKit-provided main menu; these pin the Edit key equivalents (#12).
@MainActor
@Suite struct MainMenuTests {
    struct Expected: Sendable, CustomStringConvertible {
        let action: String
        let key: String
        let shift: Bool
        var description: String { action }
        var modifiers: NSEvent.ModifierFlags { shift ? [.command, .shift] : [.command] }
    }

    nonisolated static let editItems: [Expected] = [
        Expected(action: "undo:", key: "z", shift: false),
        Expected(action: "redo:", key: "z", shift: true),
        Expected(action: "cut:", key: "x", shift: false),
        Expected(action: "copy:", key: "c", shift: false),
        Expected(action: "paste:", key: "v", shift: false),
        Expected(action: "selectAll:", key: "a", shift: false),
    ]

    private func editMenu(_ menu: NSMenu) -> NSMenu? {
        menu.items.first { $0.submenu?.title == "Edit" }?.submenu
    }

    @Test(arguments: editItems)
    func editMenuHasStandardKeyEquivalents(_ expected: Expected) throws {
        let edit = try #require(editMenu(MainMenu.make(appName: "Switch Profile")))
        let item = try #require(edit.items.first { $0.action == Selector(expected.action) })
        #expect(item.keyEquivalent == expected.key)
        #expect(item.keyEquivalentModifierMask == expected.modifiers)
        #expect(item.target == nil)
    }

    /// No Cmd+Q/W/H: quit and close behaviour is unchanged.
    @Test func appMenuIsFirstAndAddsNoShortcuts() throws {
        let menu = MainMenu.make(appName: "Switch Profile")
        let appItem = try #require(menu.items.first)
        #expect(appItem.title == "Switch Profile")
        let submenu = try #require(appItem.submenu)
        #expect(submenu.items.allSatisfy { $0.keyEquivalent.isEmpty })
    }

    @Test func installSetsTheApplicationMainMenu() throws {
        let application = NSApplication.shared
        MainMenu.install(in: application, appName: "Switch Profile")
        let installed = try #require(application.mainMenu)
        let edit = try #require(editMenu(installed))
        for (action, key) in [("paste:", "v"), ("copy:", "c"), ("cut:", "x"), ("selectAll:", "a"), ("undo:", "z")] {
            let item = edit.items.first { $0.action == Selector(action) }
            #expect(item?.keyEquivalent == key, "\(action)")
        }
    }
}
