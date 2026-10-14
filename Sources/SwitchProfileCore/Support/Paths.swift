import Foundation

/// Locations of Google Chrome (stable, default user data directory) data. Pure path computation.
public enum ChromePaths {
    /// `<home>/Library/Application Support/Google/Chrome`
    public static func userDataDirectory(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true)
    }

    /// `<userDataDirectory>/Local State`
    public static func localState(home: URL) -> URL {
        userDataDirectory(home: home).appendingPathComponent("Local State", isDirectory: false)
    }
}

/// Locations of Switch Profile's own data. Pure path computation.
public enum AppPaths {
    /// `<home>/Library/Application Support/SwitchProfile`
    public static func supportDirectory(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/SwitchProfile", isDirectory: true)
    }

    /// `<supportDirectory>/config.json`
    public static func configFile(home: URL) -> URL {
        supportDirectory(home: home).appendingPathComponent("config.json", isDirectory: false)
    }
}
