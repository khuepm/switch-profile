import Foundation
@testable import SwitchProfileCore

/// A locator with a configurable application URL and bundle identifier.
struct FakeLocator: ChromeLocating {
    static let chromeURL = URL(fileURLWithPath: "/Applications/Google Chrome.app", isDirectory: true)

    var url: URL? = FakeLocator.chromeURL
    var bundleID: String? = ChromeApp.bundleIdentifier

    func chromeApplicationURL() -> URL? { url }
    func bundleIdentifier(at url: URL) -> String? { bundleID }
}

struct FakeOpenError: LocalizedError {
    var errorDescription: String? { "fake open failure" }
}

/// Records every request. Can fail chosen calls and suspend chosen calls until `resume(_:)`.
/// Calls are numbered from 1 in the order they enter `open`.
@MainActor
final class FakeOpener: ApplicationOpening {
    private(set) var requests: [LaunchRequest] = []
    /// Call numbers that throw `FakeOpenError` (after any suspension).
    var failingCalls: Set<Int> = []
    /// Call numbers that suspend on entry until `resume(n)`.
    var suspendedCalls: Set<Int> = []

    private var suspended: [Int: CheckedContinuation<Void, Never>] = [:]
    private var resumedEarly: Set<Int> = []
    private var startWaiters: [(call: Int, continuation: CheckedContinuation<Void, Never>)] = []

    var callCount: Int { requests.count }

    /// The `--profile-directory` value of each call.
    var directories: [String] {
        requests.map { String($0.arguments[0].dropFirst("--profile-directory=".count)) }
    }

    /// The URL argument of each call.
    var urls: [String] {
        requests.map { $0.arguments[1] }
    }

    func open(_ request: LaunchRequest) async throws {
        requests.append(request)
        let call = requests.count
        let ready = startWaiters.filter { $0.call <= call }
        startWaiters.removeAll { $0.call <= call }
        for waiter in ready { waiter.continuation.resume() }

        if suspendedCalls.contains(call), !resumedEarly.contains(call) {
            await withCheckedContinuation { suspended[call] = $0 }
        }
        if failingCalls.contains(call) { throw FakeOpenError() }
    }

    /// Lets suspended call `n` continue (or pre-releases it if it has not started yet).
    func resume(_ n: Int) {
        if let continuation = suspended.removeValue(forKey: n) {
            continuation.resume()
        } else {
            resumedEarly.insert(n)
        }
    }

    /// Returns once call `n` (1-based) has entered `open`; immediately if it already has.
    func waitUntilCallStarted(_ n: Int) async {
        if requests.count >= n { return }
        await withCheckedContinuation { startWaiters.append((n, $0)) }
    }
}
