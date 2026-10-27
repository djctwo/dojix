import Foundation

/// Where UI tests tell the app to keep its data.
///
/// The UI-test runner is sandboxed, so its NSTemporaryDirectory() is inside the
/// runner's own container (~/Library/Containers/...). Pointing the (unsandboxed) app
/// there makes macOS ask "Dojix wants to access data from other apps". Use a plain
/// folder outside any container instead: `DOJIX_UITEST_ROOT` if set (CI sets it),
/// else /tmp.
enum UITestPaths {
    static var scratchRoot: String {
        if let root = ProcessInfo.processInfo.environment["DOJIX_UITEST_ROOT"], !root.isEmpty {
            return root
        }
        return "/tmp"
    }
}
