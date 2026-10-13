import Foundation

/// Configuration failures. Produced by `ConfigStore` and the `ConfigController` write guard.
public enum ConfigError: Error, Equatable, Sendable {
    case unreadable(String)
    case corrupt(String)
    case unsupportedVersion(Int)
    case writeFailed(String)
}

/// Result of loading the configuration file.
public enum ConfigState: Equatable, Sendable {
    case loaded(AppConfig)
    case absent
    case unavailable(ConfigError)
}

/// What the router sees: a usable configuration or the reason there is none. Never `.absent`.
public enum RoutingConfig: Equatable, Sendable {
    case loaded(AppConfig)
    case unavailable(ConfigError)
}
