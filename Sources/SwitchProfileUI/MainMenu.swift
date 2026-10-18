import AppKit

/// The application's main menu: an app item with an empty submenu and a standard Edit menu.
///
/// Switch Profile is an agent app (`LSUIElement`), so its menu bar is never shown and AppKit
/// installs no main menu for it. Without one, Cmd+X/C/V/A/Z have no menu item to match, and
/// text fields in Settings cannot cut, copy, paste, select all or undo from the keyboard (#12).
/// The Edit items have a nil target, so each action goes to the current first responder.
///
/// The app submenu is empty on purpose: Cmd+Q/Cmd+W/Cmd+H would change quit and close
/// behaviour. Quit stays in the status item menu.
@MainActor
public enum MainMenu {
    public static func make(appName: String) -> NSMenu {
        let mainMenu = NSMenu(title: "Main Menu")

        let appItem = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
        appItem.submenu = NSMenu(title: appName)
        mainMenu.addItem(appItem)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(item("Undo", Selector(("undo:")), "z"))
        editMenu.addItem(item("Redo", Selector(("redo:")), "z", [.command, .shift]))
        editMenu.addItem(.separator())
        editMenu.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        editMenu.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        editMenu.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        editMenu.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        return mainMenu
    }

    public static func install(in application: NSApplication, appName: String) {
        application.mainMenu = make(appName: appName)
    }

    private static func item(_ title: String, _ action: Selector, _ key: String,
                             _ modifiers: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = nil
        return item
    }
}
