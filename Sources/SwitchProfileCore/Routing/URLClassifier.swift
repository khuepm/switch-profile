import Foundation

/// Pure URL → rule classification. Normalized values are used only for comparison;
/// the forwarded URL is always the original `absoluteString`.
public enum URLClassifier {
    /// 512 KiB. The URL travels to Chrome as one argv element and `ARG_MAX` (argv + envp) is 1 MiB.
    public static let maxURLBytes = 524_288

    /// `rules` are checked in order and the first match wins; no match is the fallback (`R4`).
    public static func classify(_ url: URL, rules: [RoutingRule]) -> Classification {
        // 1. Length.
        guard url.absoluteString.utf8.count <= maxURLBytes else {
            return .rejected(.malformed(.tooLong))
        }
        // 2. Components.
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .rejected(.malformed(.unparseable))
        }
        // 3. Scheme, case-insensitive (RFC 3986); only http and https.
        guard let rawScheme = components.scheme else {
            return .rejected(.malformed(.missingScheme))
        }
        let scheme = rawScheme.lowercased()
        guard scheme == "http" || scheme == "https" else {
            return .rejected(.unsupportedScheme(scheme))
        }
        // 4. Host: the decoded host (after Foundation's IDNA mapping), lowercased, one trailing dot
        //    removed. Port and userinfo are ignored. Exact host only, no subdomain matching.
        guard let rawHost = components.host, !rawHost.isEmpty else {
            return .rejected(.malformed(.missingHost))
        }
        let host = HostName.normalize(rawHost)
        guard !host.isEmpty else {
            return .rejected(.malformed(.missingHost))
        }

        // 5. First matching rule in list order.
        let path = components.percentEncodedPath
        if let rule = rules.first(where: { $0.match.matches(host: host, percentEncodedPath: path) }) {
            return .matched(rule.id, explanation: rule.match.summary)
        }
        return .matched(.fallback, explanation: "host \(host) matches no rule; fallback")
    }
}
