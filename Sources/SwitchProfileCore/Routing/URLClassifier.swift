import Foundation

/// Pure URL → rule classification. Normalized values are used only for comparison;
/// the forwarded URL is always the original `absoluteString`.
public enum URLClassifier {
    /// 512 KiB. The URL travels to Chrome as one argv element and `ARG_MAX` (argv + envp) is 1 MiB.
    public static let maxURLBytes = 524_288

    static let fisGitLabHost = "git.fis.vn"
    static let gitHubHost = "github.com"
    static let truckerPointsOwner = "truckerpoints"
    static let truckerPointsRepos: Set<String> = ["trucker-points", "trucker-points.git"]

    public static func classify(_ url: URL) -> Classification {
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
        var host = rawHost.lowercased()
        if host.hasSuffix(".") {
            host.removeLast()
        }
        guard !host.isEmpty else {
            return .rejected(.malformed(.missingHost))
        }

        switch host {
        case fisGitLabHost:
            return .matched(.r1, explanation: "host \(fisGitLabHost)")
        case gitHubHost:
            if isTruckerPointsRepository(percentEncodedPath: components.percentEncodedPath) {
                return .matched(.r2, explanation: "host \(gitHubHost), repository TruckerPoints/trucker-points")
            }
            return .matched(.r3, explanation: "host \(gitHubHost)")
        default:
            return .matched(.r4, explanation: "host \(host) matches no rule; fallback")
        }
    }

    /// Segment 1 decodes to `truckerpoints` and segment 2 to `trucker-points` or `trucker-points.git`.
    /// Splitting keeps empty pieces (segment 0 is the empty string before the leading `/`), so
    /// `//TruckerPoints//…` does not match. Each segment is percent-decoded, then lowercased, then
    /// compared as a whole (`.git` suffix compared case-insensitively, so `trucker-points.GIT` matches).
    /// Anything after segment 2 is allowed. Query and fragment never take part.
    private static func isTruckerPointsRepository(percentEncodedPath: String) -> Bool {
        let segments = percentEncodedPath.components(separatedBy: "/")
        guard segments.count >= 3,
              let owner = segments[1].removingPercentEncoding?.lowercased(),
              let repo = segments[2].removingPercentEncoding?.lowercased()
        else {
            return false
        }
        return owner == truckerPointsOwner && truckerPointsRepos.contains(repo)
    }
}
