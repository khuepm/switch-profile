import Foundation

/// The kinds of match a rule can use. There is no wildcard or subdomain kind.
public enum RuleMatchType: String, Codable, CaseIterable, Sendable {
    /// Exact host, any path.
    case host
    /// Exact host plus a path prefix on whole segments.
    case hostPathPrefix
}

/// What a routing rule matches. Hosts are stored normalized (lowercased, no trailing dot);
/// a path prefix is stored as entered, starting with `/`, without a trailing `/`.
///
/// JSON: `{"type":"host","host":"git.fis.vn"}` or
/// `{"type":"hostPathPrefix","host":"github.com","pathPrefix":"/TruckerPoints/trucker-points"}`.
/// Decoding runs the same syntax validation as Settings; an invalid value is a decoding error.
public enum RuleMatch: Hashable, Sendable {
    case host(String)
    case hostPathPrefix(host: String, pathPrefix: String)

    public var type: RuleMatchType {
        switch self {
        case .host: .host
        case .hostPathPrefix: .hostPathPrefix
        }
    }

    public var host: String {
        switch self {
        case .host(let host), .hostPathPrefix(let host, _): host
        }
    }

    /// nil for `.host`.
    public var pathPrefix: String? {
        if case .hostPathPrefix(_, let pathPrefix) = self { return pathPrefix }
        return nil
    }

    /// For explanations: `host git.fis.vn` or `host github.com, path /TruckerPoints/trucker-points`.
    public var summary: String {
        switch self {
        case .host(let host): "host \(host)"
        case .hostPathPrefix(let host, let pathPrefix): "host \(host), path \(pathPrefix)"
        }
    }

    /// Percent-decoded, lowercased path prefix segments; empty for `.host`.
    var prefixSegments: [String] {
        guard let pathPrefix else { return [] }
        return PathPrefix.segments(pathPrefix) ?? []
    }

    /// Identity for duplicate and shadow checks: type, host and comparable segments.
    struct Key: Hashable {
        let type: RuleMatchType
        let host: String
        let segments: [String]
    }

    var key: Key { Key(type: type, host: host, segments: prefixSegments) }

    /// `host` is already normalized (`HostName.normalize`); `percentEncodedPath` is the URL's
    /// path as received. Query and fragment never take part.
    func matches(host urlHost: String, percentEncodedPath: String) -> Bool {
        guard urlHost == host else { return false }
        switch self {
        case .host:
            return true
        case .hostPathPrefix:
            return PathPrefix.matches(prefixSegments, percentEncodedPath: percentEncodedPath)
        }
    }
}

extension RuleMatch: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, host, pathPrefix
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(RuleMatchType.self, forKey: .type)
        let host = try container.decode(String.self, forKey: .host)
        let pathPrefix: String
        switch type {
        case .host: pathPrefix = ""
        case .hostPathPrefix: pathPrefix = try container.decode(String.self, forKey: .pathPrefix)
        }
        let validation = RuleValidator.match(type: type, host: host, pathPrefix: pathPrefix)
        guard let match = validation.match else {
            let names = validation.errors.map { String(describing: $0) }.joined(separator: ", ")
            throw DecodingError.dataCorruptedError(forKey: .host, in: container,
                                                   debugDescription: "invalid rule match (\(names))")
        }
        self = match
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(host, forKey: .host)
        try container.encodeIfPresent(pathPrefix, forKey: .pathPrefix)
    }
}

/// Host comparison form shared by the classifier and the validator.
public enum HostName {
    /// Lowercased, one trailing dot removed.
    public static func normalize(_ host: String) -> String {
        var normalized = host.lowercased()
        if normalized.hasSuffix(".") {
            normalized.removeLast()
        }
        return normalized
    }
}

/// Path prefix segments and segment-boundary matching.
enum PathPrefix {
    /// The prefix without its leading `/` and one trailing `/`, split on `/`, each piece
    /// percent-decoded and lowercased. nil when a piece does not percent-decode.
    static func segments(_ pathPrefix: String) -> [String]? {
        var body = Substring(pathPrefix)
        if body.hasPrefix("/") { body = body.dropFirst() }
        if body.hasSuffix("/") { body = body.dropLast() }
        var result: [String] = []
        for piece in body.split(separator: "/", omittingEmptySubsequences: false) {
            guard let decoded = String(piece).removingPercentEncoding else { return nil }
            result.append(decoded.lowercased())
        }
        return result
    }

    /// Splitting keeps empty pieces (piece 0 is the empty string before the leading `/`), so
    /// `//owner/repo` does not match `/owner/repo`. Each URL piece is percent-decoded, then
    /// lowercased, then compared as a whole; the last prefix segment also matches `<segment>.git`.
    /// Anything after the prefix is allowed.
    static func matches(_ prefix: [String], percentEncodedPath: String) -> Bool {
        guard !prefix.isEmpty else { return false }
        let pieces = percentEncodedPath.components(separatedBy: "/")
        guard pieces.count > prefix.count else { return false }
        for (index, segment) in prefix.enumerated() {
            guard let decoded = pieces[index + 1].removingPercentEncoding?.lowercased() else { return false }
            let isLast = index == prefix.count - 1
            guard decoded == segment || (isLast && decoded == segment + ".git") else { return false }
        }
        return true
    }
}
