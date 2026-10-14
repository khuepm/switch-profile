// swift-tools-version:6.0
import Foundation
import PackageDescription

// Under Command Line Tools (no Xcode), SwiftPM's default build system does not pass the
// swift-testing macro plugin directory to the compiler, so `@Test` fails with
// "plugin for module 'TestingMacros' not found". Point the test target at the CLT plugin
// directory; the flag is only added when that directory exists.
let cltTestingPlugins = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
let testSwiftSettings: [SwiftSetting] = FileManager.default.fileExists(atPath: cltTestingPlugins)
    ? [.unsafeFlags(["-plugin-path", cltTestingPlugins])]
    : []

let package = Package(
    name: "SwitchProfile",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "SwitchProfile", targets: ["SwitchProfileApp"]),
        .library(name: "SwitchProfileCore", targets: ["SwitchProfileCore"]),
    ],
    targets: [
        .target(name: "SwitchProfileCore"),
        .executableTarget(name: "SwitchProfileApp", dependencies: ["SwitchProfileCore"]),
        .testTarget(
            name: "SwitchProfileCoreTests",
            dependencies: ["SwitchProfileCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: testSwiftSettings
        ),
    ]
)
