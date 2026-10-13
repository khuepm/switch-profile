import AppKit
import SwitchProfileCore

/// `SwitchProfile --dry-run [--assume-chrome running|closed] [--local-state PATH] [--config PATH] URL…`
///
/// Runs each URL through the real `Router.decide` and `ChromeLauncher.makeRequest` and prints the exact
/// launch request. Strictly synchronous: it never launches an application, never changes the default
/// browser and never writes a file (SourceInvariantTests check (f)). Output contains profile directory
/// keys only, never emails or display names.
enum DryRunCommand {
    static let usage = """
        usage: SwitchProfile --dry-run [--assume-chrome running|closed] [--local-state PATH] [--config PATH] URL...

          --assume-chrome running|closed  report as if Chrome were running or closed (default: detected)
          --local-state PATH              Chrome Local State file (default: the Chrome stable user data directory)
          --config PATH                   Switch Profile configuration (default: ~/Library/Application Support/SwitchProfile/config.json)

        Prints the routing decision and the exact Chrome argv for each URL. Nothing is opened or written.
        Exit status: 0 if every URL would launch, 2 otherwise, 64 for usage errors.
        """

    static let exitLaunchable: Int32 = 0
    static let exitNotLaunchable: Int32 = 2
    static let exitUsage: Int32 = 64

    private struct Options {
        var assumeChromeRunning: Bool?
        var localState: URL?
        var config: URL?
        var urls: [String] = []
    }

    /// Never opens anything: `makeRequest` does not use the opener, and this one refuses if called.
    private struct RefusingOpener: ApplicationOpening {
        struct Refused: Error {}
        func open(_ request: LaunchRequest) async throws { throw Refused() }
    }

    @MainActor
    static func run(_ arguments: [String]) -> Int32 {
        guard let options = parse(arguments) else {
            FileHandle.standardError.write(Data((usage + "\n").utf8))
            return exitUsage
        }
        let home = FileManager.default.homeDirectoryForCurrentUser

        // Catalog (read only).
        let localStateURL = options.localState ?? ChromePaths.localState(home: home)
        let catalog: CatalogState
        do throws(LocalStateError) {
            catalog = .loaded(try LocalStateLoader.load(from: localStateURL))
        } catch {
            catalog = .unavailable(error)
        }

        // Configuration (read only; seeding stays in memory).
        let configURL = options.config ?? AppPaths.configFile(home: home)
        var notes: [String] = []
        var routingConfig: RoutingConfig
        switch ConfigStore(fileURL: configURL).load() {
        case .loaded(let loaded):
            routingConfig = .loaded(loaded)
            notes.append("config: \(configURL.path) (loaded)")
        case .absent:
            routingConfig = .loaded(.unseededDefault)
            notes.append("config: \(configURL.path) (absent, using built-in defaults)")
        case .unavailable(let error):
            routingConfig = .unavailable(error)
            notes.append("config: \(configURL.path) (unavailable: \(error))")
        }
        if case .loaded(let config) = routingConfig, config.seedPending, case .loaded(let profiles) = catalog {
            routingConfig = .loaded(ConfigSeeder.seed(config, catalog: profiles))
            notes.append("note: config seeded in memory (not saved)")
        }

        switch catalog {
        case .loaded(let profiles):
            notes.insert("local-state: \(localStateURL.path) (\(profiles.profiles.count) profiles)", at: 0)
        case .unavailable(let error):
            notes.insert("local-state: \(localStateURL.path) (unavailable: \(error))", at: 0)
        }

        // Chrome state.
        let chromeRunning: Bool
        if let assumed = options.assumeChromeRunning {
            chromeRunning = assumed
            notes.append("chrome: \(assumed ? "running" : "closed") (assumed)")
        } else {
            chromeRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: ChromeApp.bundleIdentifier).isEmpty
            notes.append("chrome: \(chromeRunning ? "running" : "closed") (detected)")
        }

        let locator = WorkspaceApplicationOpener()
        let launcher = ChromeLauncher(locator: locator, opener: RefusingOpener(),
                                      ownBundleIdentifier: Bundle.main.bundleIdentifier ?? "io.github.khuepm.switchprofile")

        var blocks = [notes.joined(separator: "\n")]
        var allLaunchable = true
        for text in options.urls {
            guard let url = URL(string: text) else {
                blocks.append("url: \(text)\ndecision: rejected, not a valid URL\nlaunch: none")
                allLaunchable = false
                continue
            }
            let decision = Router.decide(url, config: routingConfig, catalog: catalog)
            var request: Result<LaunchRequest, LaunchError>?
            if case .launch(let target, _) = decision {
                do throws(LaunchError) {
                    request = .success(try launcher.makeRequest(for: target))
                } catch {
                    request = .failure(error)
                }
            }
            if case .success = request {} else { allLaunchable = false }
            blocks.append(DryRunReport.render(url: url, decision: decision, request: request, chromeRunning: chromeRunning))
        }
        print(blocks.joined(separator: "\n\n"))
        return allLaunchable ? exitLaunchable : exitNotLaunchable
    }

    private static func parse(_ arguments: [String]) -> Options? {
        var options = Options()
        var index = 0
        func value() -> String? {
            index += 1
            return index < arguments.count ? arguments[index] : nil
        }
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--assume-chrome":
                switch value() {
                case "running": options.assumeChromeRunning = true
                case "closed": options.assumeChromeRunning = false
                default: return nil
                }
            case "--local-state":
                guard let path = value() else { return nil }
                options.localState = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            case "--config":
                guard let path = value() else { return nil }
                options.config = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            case "--":
                options.urls.append(contentsOf: arguments[(index + 1)...])
                index = arguments.count
            default:
                if argument.hasPrefix("-") { return nil }   // includes --help and -h
                options.urls.append(argument)
            }
            index += 1
        }
        return options.urls.isEmpty ? nil : options
    }
}
