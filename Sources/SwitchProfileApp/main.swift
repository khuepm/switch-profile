import AppKit

// Headless launcher preview: routes and prints the exact Chrome request, never opens or writes anything.
if CommandLine.arguments.dropFirst().first == "--dry-run" {
    exit(DryRunCommand.run(Array(CommandLine.arguments.dropFirst(2))))
}

let delegate = AppDelegate()               // NSApplication.delegate is weak; this top-level constant keeps it alive
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
