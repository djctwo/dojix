import Foundation

/// What Settings needs from App Lock. `AppState` implements it; tests use a fake.
@MainActor
protocol AppLockActions: AnyObject {
    /// Whether App Lock is on right now.
    var isAppLockOn: Bool { get }
    /// Turn App Lock on with `password` (rotates the database key).
    func enableAppLock(password: String) async throws -> KeyRotation.Outcome
    /// Change the App Lock password (needs the current one; rotates the database key).
    func changeAppLockPassword(current: String, new: String) async throws -> KeyRotation.Outcome
    /// Turn App Lock off (needs the current password).
    func disableAppLock(password: String) async throws
}

extension AppState: AppLockActions {}
