import Foundation

extension Error {
    /// Human-readable error message for file/export/backup operations.
    /// Maps common NSError codes to plain-language descriptions.
    var friendlyMessage: String {
        let nsError = self as NSError
        switch nsError.code {
        case 4, 513:
            return "Couldn't save the file — check that the location is writable"
        case 260:
            return "The save location no longer exists — try a different folder"
        case 516:
            return "A file with that name already exists and can't be replaced"
        case -1009, -1004:
            return "No internet connection — check your network and try again"
        case -1001:
            return "The request timed out — try again in a moment"
        default:
            return "Something went wrong — try again or contact support"
        }
    }
}
