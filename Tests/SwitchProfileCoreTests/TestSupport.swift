import Foundation
@testable import SwitchProfileCore

/// Access to the synthetic fixtures copied into the test bundle.
enum Fixture {
    static func url(_ name: String) -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            fatalError("missing fixture \(name).json")
        }
        return url
    }

    static func data(_ name: String) -> Data {
        // Fixtures are part of the test bundle; a read failure is a broken build.
        try! Data(contentsOf: url(name))
    }

    /// The catalog parsed from `local-state-valid.json`.
    static func validCatalog() -> ProfileCatalog {
        try! LocalStateLoader.parse(data("local-state-valid"))
    }
}

/// A fresh temporary directory, removed by `cleanup()`.
struct TempDir {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwitchProfileTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func cleanup() {
        // Restore permissions changed by tests so removal succeeds.
        if let enumerator = FileManager.default.enumerator(atPath: url.path) {
            for case let relative as String in enumerator {
                try? FileManager.default.setAttributes([.posixPermissions: 0o700],
                                                       ofItemAtPath: url.appendingPathComponent(relative).path)
            }
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        try? FileManager.default.removeItem(at: url)
    }
}
