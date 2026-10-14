import Foundation
import Testing
@testable import SwitchProfileCore

@Suite struct PathsTests {
    let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

    @Test func chromePaths() {
        #expect(ChromePaths.userDataDirectory(home: home).path == "/Users/tester/Library/Application Support/Google/Chrome")
        #expect(ChromePaths.localState(home: home).path == "/Users/tester/Library/Application Support/Google/Chrome/Local State")
    }

    @Test func appPaths() {
        #expect(AppPaths.supportDirectory(home: home).path == "/Users/tester/Library/Application Support/SwitchProfile")
        #expect(AppPaths.configFile(home: home).path == "/Users/tester/Library/Application Support/SwitchProfile/config.json")
    }

    @Test func logSubsystem() {
        #expect(Log.subsystem == "io.github.khuepm.switchprofile")
    }
}
