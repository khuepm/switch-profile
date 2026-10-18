import Foundation
import Testing
@testable import SwitchProfileCore

/// Static text checks over `Sources/` (design §11, plan D6). Comments are stripped first, so doc
/// comments naming a type are not violations; string literals are kept.
@Suite struct SourceInvariantTests {
    struct SourceFile {
        /// Relative to `Sources/`, e.g. `SwitchProfileCore/Support/Paths.swift`.
        let path: String
        /// Comment-stripped text.
        let code: String
    }

    static let sourcesDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // SwitchProfileCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // package root
        .appendingPathComponent("Sources", isDirectory: true)

    static func sourceFiles() throws -> [SourceFile] {
        let root = sourcesDirectory.standardizedFileURL.path
        guard let enumerator = FileManager.default.enumerator(atPath: root) else { return [] }
        var files: [SourceFile] = []
        for case let relative as String in enumerator where relative.hasSuffix(".swift") {
            let text = try String(contentsOfFile: root + "/" + relative, encoding: .utf8)
            files.append(SourceFile(path: relative, code: stripComments(text)))
        }
        return files.sorted { $0.path < $1.path }
    }

    /// Paths (relative to `Sources/`) whose code contains the identifier `name` as a whole word.
    static func files(referencing name: String, in files: [SourceFile]) -> Set<String> {
        let pattern = "\\b\(name)\\b"
        return Set(files.filter { $0.code.range(of: pattern, options: .regularExpression) != nil }.map(\.path))
    }

    static let appDelegate = "SwitchProfileApp/AppDelegate.swift"
    static let dryRunCommand = "SwitchProfileApp/DryRunCommand.swift"

    @Test func sourcesAreFound() throws {
        let paths = Set(try Self.sourceFiles().map(\.path))
        #expect(paths.contains("SwitchProfileCore/Support/Paths.swift"))
        #expect(paths.contains(Self.appDelegate))
        #expect(paths.contains(Self.dryRunCommand))
    }

    /// (a) Core stays Foundation/os only.
    @Test func coreImportsNoUIFramework() throws {
        for file in try Self.sourceFiles() where file.path.hasPrefix("SwitchProfileCore/") {
            #expect(!file.code.contains("import AppKit"), "\(file.path)")
            #expect(!file.code.contains("import SwiftUI"), "\(file.path)")
        }
    }

    /// (b) No default-handler forwarding (loop) and no shell or subprocess anywhere.
    @Test(arguments: ["NSWorkspace.shared.open(", ".open(urls", "withApplicationAt", "LSOpenCFURLRef",
                      "Process(", "/bin/sh", "/bin/zsh", "/usr/bin/open"])
    func noForbiddenCall(_ token: String) throws {
        for file in try Self.sourceFiles() {
            #expect(!file.code.contains(token), "\(file.path) contains \(token)")
        }
    }

    /// (c) Chrome's data path is built in one place; only the composition roots reference it.
    @Test func chromePathsAreConfined() throws {
        let files = try Self.sourceFiles()
        let literal = Set(files.filter { $0.code.contains("Google/Chrome") }.map(\.path))
        #expect(literal == ["SwitchProfileCore/Support/Paths.swift"])
        #expect(Self.files(referencing: "ChromePaths", in: files)
            .isSubset(of: ["SwitchProfileCore/Support/Paths.swift", Self.appDelegate, Self.dryRunCommand]))
    }

    /// (d) Only the controller (and the composition roots that build it) hold a store.
    @Test func configStoreIsConfined() throws {
        let allowed: Set = ["SwitchProfileCore/Config/ConfigStore.swift", "SwitchProfileCore/Config/ConfigController.swift",
                            Self.appDelegate, Self.dryRunCommand]
        #expect(Self.files(referencing: "ConfigStore", in: try Self.sourceFiles()).isSubset(of: allowed))
    }

    /// (e) Only the coordinator can launch.
    @Test func chromeLauncherIsConfined() throws {
        let allowed: Set = ["SwitchProfileCore/Launch/ChromeLauncher.swift", "SwitchProfileCore/Intake/RoutingCoordinator.swift",
                            Self.appDelegate, Self.dryRunCommand]
        #expect(Self.files(referencing: "ChromeLauncher", in: try Self.sourceFiles()).isSubset(of: allowed))
    }

    /// (f) The dry run cannot launch, write or change the default browser.
    @Test(arguments: ["await", ".save(", ".update(", "openApplication", "setDefaultApplication"])
    func dryRunIsSynchronousAndReadOnly(_ token: String) throws {
        let file = try #require(try Self.sourceFiles().first { $0.path == Self.dryRunCommand })
        #expect(!file.code.contains(token), "DryRunCommand.swift contains \(token)")
    }

    /// (g) The agent app installs a main menu so text fields get Cmd+X/C/V/A/Z (#12).
    @Test func appDelegateInstallsTheMainMenu() throws {
        let file = try #require(try Self.sourceFiles().first { $0.path == Self.appDelegate })
        #expect(file.code.contains("MainMenu.install("))
    }

    /// (h) Settings has no routing preview; routing is checked with `--dry-run` (#12).
    @Test(arguments: ["\"Check rule\"", "\"Open test link\"", "\"Test a link\"", "checkRule", "openTestLink"])
    func settingsHasNoRoutingPreview(_ token: String) throws {
        let files = try Self.sourceFiles()
        for path in ["SwitchProfileApp/SettingsView.swift", "SwitchProfileApp/SettingsModel.swift"] {
            let file = try #require(files.first { $0.path == path })
            #expect(!file.code.contains(token), "\(path) contains \(token)")
        }
    }

    /// (i) Only the launcher builds the profile switch, so last-active mode cannot gain one elsewhere (#13).
    @Test func profileDirectorySwitchIsBuiltOnlyByTheLauncher() throws {
        let files = try Self.sourceFiles()
        let users = Set(files.filter { $0.code.contains("--profile-directory=") }.map(\.path))
        #expect(users == ["SwitchProfileCore/Launch/ChromeLauncher.swift"])
    }

    /// (j) Chrome is opened explicitly as a new instance (`open -na` form), never through a URL's
    /// default handler; this is also how last-active mode reaches the running Chrome (#13).
    @Test func openerLaunchesChromeAsANewInstance() throws {
        let file = try #require(try Self.sourceFiles().first { $0.path == "SwitchProfileApp/WorkspaceApplicationOpener.swift" })
        #expect(file.code.contains("createsNewApplicationInstance = true"))
        #expect(file.code.contains("openApplication(at: request.applicationURL"))
    }

    /// (k) Settings offers the last active Chrome profile as the fallback option (#13).
    @Test func settingsOffersLastActiveFallback() throws {
        let file = try #require(try Self.sourceFiles().first { $0.path == "SwitchProfileApp/SettingsView.swift" })
        #expect(file.code.contains("\"Last active Chrome profile\""))
    }

    // MARK: stripComments

    @Test func stripsLineComment() {
        #expect(stripComments("let a = 1 // ChromeLauncher\nlet b = 2") == "let a = 1 \nlet b = 2")
    }

    @Test func stripsNestedBlockComment() {
        #expect(stripComments("a /* x /* ConfigStore */ y */ b") == "a  b")
    }

    @Test func keepsSlashesInsideStringLiteral() {
        let source = #"let u = "https://example.com" // tail"#
        #expect(stripComments(source) == #"let u = "https://example.com" "#)
    }

    @Test func honoursEscapedQuote() {
        let source = #"let s = "say \"// not a comment\"" /* gone */"#
        #expect(stripComments(source) == #"let s = "say \"// not a comment\"" "#)
    }

    @Test func keepsMultilineLiteralAndInterpolation() {
        let source = "let s = \"\"\"\n// kept\n\"\"\"\nlet t = \"\\(f(\"a//b\")) x\" // gone"
        #expect(stripComments(source) == "let s = \"\"\"\n// kept\n\"\"\"\nlet t = \"\\(f(\"a//b\")) x\" ")
    }
}

/// Removes `//` and (nested) `/* */` comments outside string literals. Single-line and `"""` literals
/// are kept verbatim, honouring `\` escapes and `\( … )` interpolation (which may contain literals).
func stripComments(_ source: String) -> String {
    enum Context {
        case string(multiline: Bool)
        case interpolation(depth: Int)
    }
    let chars = Array(source)
    var out = ""
    var stack: [Context] = []
    var i = 0
    func at(_ offset: Int) -> Character? {
        i + offset < chars.count ? chars[i + offset] : nil
    }

    while i < chars.count {
        let c = chars[i]

        // Inside a string literal.
        if case .string(let multiline)? = stack.last {
            if c == "\\" {
                if at(1) == "(" {
                    out += "\\("
                    i += 2
                    stack.append(.interpolation(depth: 0))
                    continue
                }
                out.append(c)
                if let next = at(1) { out.append(next) }
                i += 2
                continue
            }
            if multiline, c == "\"", at(1) == "\"", at(2) == "\"" {
                out += "\"\"\""
                i += 3
                stack.removeLast()
                continue
            }
            if !multiline, c == "\"" {
                out.append(c)
                i += 1
                stack.removeLast()
                continue
            }
            out.append(c)
            i += 1
            continue
        }

        // Code, at top level or inside an interpolation.
        if c == "/", at(1) == "/" {
            while i < chars.count, chars[i] != "\n" { i += 1 }
            continue
        }
        if c == "/", at(1) == "*" {
            var depth = 0
            while i < chars.count {
                if chars[i] == "/", at(1) == "*" {
                    depth += 1
                    i += 2
                } else if chars[i] == "*", at(1) == "/" {
                    depth -= 1
                    i += 2
                    if depth == 0 { break }
                } else {
                    i += 1
                }
            }
            continue
        }
        if c == "\"" {
            if at(1) == "\"", at(2) == "\"" {
                out += "\"\"\""
                i += 3
                stack.append(.string(multiline: true))
            } else {
                out.append(c)
                i += 1
                stack.append(.string(multiline: false))
            }
            continue
        }
        if case .interpolation(let depth)? = stack.last {
            if c == "(" {
                stack[stack.count - 1] = .interpolation(depth: depth + 1)
            } else if c == ")" {
                if depth == 0 {
                    stack.removeLast()
                } else {
                    stack[stack.count - 1] = .interpolation(depth: depth - 1)
                }
            }
        }
        out.append(c)
        i += 1
    }
    return out
}
