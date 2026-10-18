import Foundation

/// Pure text rendering of what a launch would do. Used by the headless `--dry-run` command,
/// which never opens or writes anything.
public enum DryRunReport {
    /// The header line(s) for the catalog. When it is unavailable, names the cause and the fix.
    public static func localStateNote(path: String, catalog: CatalogState) -> String {
        switch catalog {
        case .loaded(let profiles):
            "local-state: \(path) (\(profiles.profiles.count) profiles)"
        case .unavailable(let error):
            """
            local-state: \(path) (unavailable)
            error: \(CatalogMessages.unavailable(error))
            fix: \(CatalogMessages.remedy(error, requester: .terminal))
            """
        }
    }

    /// `catalogError` is the catalog's error when it is unavailable: an unseeded rule then reports
    /// `.unset`, and the line says Chrome profiles are unavailable instead of "has no profile set".
    public static func render(url: URL, decision: RoutingDecision,
                              request: Result<LaunchRequest, LaunchError>?, chromeRunning: Bool,
                              catalogError: LocalStateError? = nil) -> String {
        var lines = ["url: \(url.absoluteString)"]
        switch decision {
        case .launch(let target, let explanation):
            lines.append("decision: launch, \(explanation)")
            lines.append("profile-directory: \(target.directory)")
            lines.append("chrome-state: " + (chromeRunning
                ? "running, new instance forwards the command line to the running Chrome (ProcessSingleton)"
                : "closed, cold start; waits up to 5 s for isFinishedLaunching before the next URL"))
            switch request {
            case .success(let request):
                let application = request.applicationURL.path
                lines.append("application: \(application)")
                lines.append("argv: \(jsonArray(request.arguments))")
                let quoted = request.arguments.map(shellQuoted).joined(separator: " ")
                lines.append("equivalent (display only, never executed): open -na \(shellQuoted(application)) --args \(quoted)")
            case .failure(let error):
                lines.append("launch-error: \(describe(error))")
            case nil:
                lines.append("launch-error: request not built")
            }
        case .needsProfile(_, let rule, let issue, let explanation):
            switch (issue, catalogError) {
            case (.unset, .some):
                lines.append("decision: needs profile, Chrome profiles unavailable, so no profile can be chosen for \(rule.rawValue) (\(explanation))")
            case (.catalogUnavailable, _):
                lines.append("decision: needs profile, Chrome profiles unavailable, so the \(rule.rawValue) profile cannot be checked (\(explanation))")
            default:
                lines.append("decision: needs profile, \(rule.rawValue) \(describe(issue)) (\(explanation))")
            }
            lines.append("profile-directory: none")
            lines.append("launch: none, the link would wait in the pending window")
        case .rejected(_, let rejection):
            lines.append("decision: rejected, \(describe(rejection))")
            lines.append("launch: none")
        }
        return lines.joined(separator: "\n")
    }

    /// POSIX single-quote escaping: `'` becomes `'\''`.
    static func shellQuoted(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func jsonArray(_ strings: [String]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(strings), let text = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return text
    }

    private static func describe(_ error: LaunchError) -> String {
        switch error {
        case .chromeNotInstalled: "Google Chrome is not installed"
        case .loopDetected(let found): "loop guard, located application is \(found), not \(ChromeApp.bundleIdentifier)"
        case .openFailed(let message): "open failed, \(message)"
        }
    }

    private static func describe(_ issue: ProfileIssue) -> String {
        switch issue {
        case .unset: "has no profile set"
        case .missing(let binding): "profile directory \(binding.directory) is missing"
        case .identityMismatch(let binding, _): "profile \(binding.directory) changed account"
        case .catalogUnavailable(let error): "cannot read Chrome profiles: \(error)"
        case .configUnavailable(let error): "configuration unavailable: \(error)"
        }
    }

    private static func describe(_ rejection: Rejection) -> String {
        switch rejection {
        case .unsupportedScheme(let scheme): "unsupported scheme \(scheme)"
        case .malformed(let reason): "malformed URL (\(reason))"
        }
    }
}
