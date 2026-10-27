import Foundation
import os

/// Factory for the URLSession used by every network call in Dojix.
///
/// All endpoints are HTTPS/WSS and are validated by the operating system's normal
/// certificate checks (App Transport Security). Earlier private builds pinned
/// individual server certificates; that was removed in the open-source edition
/// because pins go stale when providers rotate certificates, and an app without
/// an update channel would then silently lose live data and AI features.
///
/// Requests carry the user's API keys in headers (`x-api-key`, `Authorization`), and
/// URLSession copies a request's headers onto a redirected request. So a redirect is
/// only followed to the same host over HTTPS: a key never reaches another server.
enum SecureSession {
    /// Create a URLSession with no response caching and the given request timeout.
    static func make(timeout: TimeInterval = 30) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        return URLSession(configuration: config, delegate: RedirectGuard(), delegateQueue: nil)
    }

    /// Whether a redirect from `original` to `target` may be followed: HTTPS (or WSS)
    /// only, and the same host.
    static func allowsRedirect(from original: URL?, to target: URL?) -> Bool {
        guard let originalHost = original?.host?.lowercased(), let target,
              let targetHost = target.host?.lowercased(),
              let scheme = target.scheme?.lowercased(), scheme == "https" || scheme == "wss" else {
            return false
        }
        return originalHost == targetHost
    }

    /// Refuses redirects that would send the request (and its API key) elsewhere.
    /// Refused: the 3xx response itself is returned, which every caller treats as an error.
    final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
        private static let logger = Logger(subsystem: "com.dojix", category: "SecureSession")

        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? {
            let original = task.originalRequest?.url ?? response.url
            guard SecureSession.allowsRedirect(from: original, to: request.url) else {
                Self.logger.warning("Refused a redirect to another host or to plain HTTP")
                return nil
            }
            return request
        }
    }
}
