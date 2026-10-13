import AppKit
import SwiftUI

/// The "Switch Profile Settings" window. Each show reloads the catalog through the model.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    let model: SettingsModel
    private let window: NSWindow

    init(model: SettingsModel) {
        self.model = model
        window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
        super.init()
        window.title = "Switch Profile Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 620, height: 760))
        window.center()
        window.delegate = self
    }

    func show() {
        model.reload()
        window.makeKeyAndOrderFront(nil)
        // Agent apps otherwise open behind other windows.
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        model.defaultBrowserStatusMayHaveChanged()
    }
}
