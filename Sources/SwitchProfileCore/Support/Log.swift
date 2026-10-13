import os

/// Unified-logging categories. Policy: rule IDs, decision kinds, directory keys and error descriptions
/// are public; URL hosts are private; full URLs, paths, queries, emails and display names are never logged.
public enum Log {
    public static let subsystem = "io.github.khuepm.switchprofile"

    public static let routing = Logger(subsystem: subsystem, category: "routing")
    public static let profiles = Logger(subsystem: subsystem, category: "profiles")
    public static let config = Logger(subsystem: subsystem, category: "config")
    public static let launch = Logger(subsystem: subsystem, category: "launch")
    public static let ui = Logger(subsystem: subsystem, category: "ui")
}
