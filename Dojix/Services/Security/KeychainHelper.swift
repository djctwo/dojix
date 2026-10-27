import Foundation
import LocalAuthentication
import Security
import os

/// Secure storage for API keys and sensitive data using macOS Keychain
enum KeychainHelper {
    private static let logger = Logger(subsystem: "com.dojix", category: "Keychain")
    private static let service = Configuration.keychainService

    /// Save a string value to the Keychain. Returns false if the Keychain refused it.
    @discardableResult
    static func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Delete existing item first
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Keychain save failed for \(key): \(status)")
        }
        return status == errSecSuccess
    }

    /// Replace a value in place (SecItemUpdate), or add it if it does not exist yet.
    /// Used for key material: unlike `save`, there is no moment where the old item has
    /// been deleted but the new one not yet written.
    /// `allowsUserInteraction` false: fail (errSecInteractionNotAllowed) instead of
    /// letting macOS show a dialog, e.g. to unlock a locked login keychain.
    @discardableResult
    static func replace(key: String, value: String, allowsUserInteraction: Bool = true) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        var match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        if !allowsUserInteraction {
            let context = LAContext()
            context.interactionNotAllowed = true
            match[kSecUseAuthenticationContext as String] = context
        }
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(match as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = match
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            if addStatus != errSecSuccess { logger.error("Keychain add failed for \(key): \(addStatus)") }
            return addStatus == errSecSuccess
        }
        if status != errSecSuccess { logger.error("Keychain update failed for \(key): \(status)") }
        return status == errSecSuccess
    }

    /// Read a string value from the Keychain, also returning the raw status so callers
    /// can tell "no such item" (errSecItemNotFound) apart from "item exists but could
    /// not be read right now" (for example a locked keychain).
    static func readWithStatus(key: String) -> (value: String?, status: OSStatus) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return (nil, status)
        }
        return (String(data: data, encoding: .utf8), status)
    }

    /// Read a string value from the Keychain
    static func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    /// Delete every Keychain item this app stored (API keys, app-lock data,
    /// database key). Used by "Erase all local data".
    static func deleteAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        // Some macOS keychains delete one match per call, so repeat until none remain.
        for _ in 0..<64 where SecItemDelete(query as CFDictionary) == errSecSuccess {}
    }

    /// Delete a value from the Keychain
    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Convenience Keys

    static var anthropicAPIKey: String? {
        get { read(key: "anthropic_api_key") }
        set {
            if let newValue, !newValue.isEmpty {
                save(key: "anthropic_api_key", value: newValue)
            } else {
                delete(key: "anthropic_api_key")
            }
        }
    }

    static var twelveDataAPIKey: String? {
        get { read(key: "twelve_data_api_key") }
        set {
            if let newValue, !newValue.isEmpty {
                save(key: "twelve_data_api_key", value: newValue)
            } else {
                delete(key: "twelve_data_api_key")
            }
        }
    }

    /// OANDA API token
    static var oandaAPIToken: String? {
        get { read(key: "oanda_api_token") }
        set {
            if let newValue, !newValue.isEmpty {
                save(key: "oanda_api_token", value: newValue)
            } else {
                delete(key: "oanda_api_token")
            }
        }
    }

    /// OANDA account ID
    static var oandaAccountID: String? {
        get { read(key: "oanda_account_id") }
        set {
            if let newValue, !newValue.isEmpty {
                save(key: "oanda_account_id", value: newValue)
            } else {
                delete(key: "oanda_account_id")
            }
        }
    }

    /// OANDA environment (true = live, false = practice/demo)
    static var oandaIsLive: Bool {
        get { read(key: "oanda_is_live") == "true" }
        set { save(key: "oanda_is_live", value: newValue ? "true" : "false") }
    }

    /// Polygon.io API key for WebSocket streaming
    static var polygonAPIKey: String? {
        get { read(key: "polygon_api_key") }
        set {
            if let newValue, !newValue.isEmpty {
                save(key: "polygon_api_key", value: newValue)
            } else {
                delete(key: "polygon_api_key")
            }
        }
    }

    /// Selected live data source (stored in UserDefaults — not sensitive)
    static var liveDataSource: LiveDataSource {
        get {
            guard let raw = UserDefaults.standard.string(forKey: "live_data_source"),
                  let source = LiveDataSource(rawValue: raw) else {
                return .twelveDataREST
            }
            return source
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "live_data_source")
        }
    }

    /// Migrate API key from UserDefaults to Keychain (one-time)
    /// `read` / `save` default to the Keychain; tests pass stand-ins.
    static func migrateFromUserDefaults(
        defaults: UserDefaults = .standard,
        read: (String) -> String? = { KeychainHelper.read(key: $0) },
        save: (String, String) -> Bool = { KeychainHelper.save(key: $0, value: $1) }
    ) {
        guard let key = defaults.string(forKey: "anthropic_api_key"), !key.isEmpty else { return }
        if read("anthropic_api_key") == nil {
            // Keep the only copy if the Keychain refuses it (tried again next launch).
            guard save("anthropic_api_key", key) else {
                logger.error("Could not move the Anthropic API key to the Keychain")
                return
            }
            logger.info("Migrated Anthropic API key from UserDefaults to Keychain")
        }
        // The Keychain holds a key now (this one or a newer one): drop the plaintext copy
        // from the preferences file.
        defaults.removeObject(forKey: "anthropic_api_key")
    }
}
