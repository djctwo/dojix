import AppKit

/// What locking needs from AppKit to make sure no journal data stays on screen: the
/// lock screen replaces the main window's content, and anything presented on top of it
/// is closed. Abstracted so the behaviour is unit-tested without real windows.
@MainActor
protocol ModalUIHost: AnyObject {
    /// A modal session (an open/save panel or alert run with `runModal`) is running.
    var hasModalSession: Bool { get }
    /// End it as if cancelled (`runModal` returns `.abort`, so nothing is exported).
    func abortModalSession()
    /// Close every sheet (and SwiftUI alert/sheet) attached to a window.
    func endAllSheets()
}

extension NSApplication: ModalUIHost {
    var hasModalSession: Bool { modalWindow != nil }

    func abortModalSession() {
        abortModal()
    }

    func endAllSheets() {
        for window in windows {
            while let sheet = window.attachedSheet {
                window.endSheet(sheet, returnCode: .abort)
                if window.attachedSheet === sheet { break } // refused: don't loop
            }
        }
    }
}

enum LockCover {
    /// Close modal panels, alerts and sheets, so only the lock screen is visible.
    @MainActor
    static func dismissModalUI(in host: ModalUIHost = NSApplication.shared) {
        if host.hasModalSession {
            host.abortModalSession()
        }
        host.endAllSheets()
    }
}
