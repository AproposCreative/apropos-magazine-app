import Foundation
import OSLog
import Security

/// Secure configuration manager for API keys and sensitive data
class SecureConfig {
    static let shared = SecureConfig()
    
    private let logger = Logger(subsystem: "com.aproposmagazine.app", category: "SecureConfig")
    private let secrets: [String: Any] = SecureConfig.loadSecrets()
    
    private init() {}
    
    // MARK: - Keychain Operations
    
    /// Store API key securely in keychain
    func storeAPIKey(_ key: String, for service: String) -> Bool {
        let data = key.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "api_key",
            kSecValueData as String: data
        ]
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    /// Retrieve API key from keychain
    func getAPIKey(for service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "api_key",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return key
    }
    
    // MARK: - Helpers
    
    private static func loadSecrets() -> [String: Any] {
        if let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
           let dict = NSDictionary(contentsOf: url) as? [String: Any] {
            return dict
        }
        
        return [:]
    }
    
    private func sanitizeSecret(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              trimmed.lowercased().hasPrefix("your-") == false,
              trimmed.contains("example.com") == false else {
            return nil
        }
        return trimmed
    }
    
    private func secretValue(for plistKey: String, service: String, envKey: String) -> String? {
        if let keychainValue = sanitizeSecret(getAPIKey(for: service)) {
            return keychainValue
        }
        
        if let plistValue = sanitizeSecret(secrets[plistKey] as? String) {
            return plistValue
        }
        
        if let envValue = sanitizeSecret(ProcessInfo.processInfo.environment[envKey]) {
            return envValue
        }
        
        return nil
    }
    
    // MARK: - API Key Getters
    
    var webflowAPIKey: String {
        ""
    }
    
    var googleAPIKey: String {
        return secretValue(for: "GOOGLE_API_KEY", service: "google", envKey: "GOOGLE_API_KEY") ?? ""
    }
    
    var openAIAPIKey: String {
        return secretValue(for: "OPENAI_API_KEY", service: "openai", envKey: "OPENAI_API_KEY") ?? ""
    }
    
    var fcmBackendURL: URL? {
        guard let rawValue = secretValue(for: "FCM_BACKEND_URL", service: "fcm_backend_url", envKey: "FCM_BACKEND_URL"),
              let url = URL(string: rawValue) else {
            return nil
        }
        return url
    }
}

// MARK: - Setup Helper
extension SecureConfig {
    /// Call this method during app launch to set up API keys
    /// This should be called from AppDelegate or SceneDelegate
    func setupAPIKeys() {
        // For development, you can set environment variables
        // For production, use keychain storage
        
        #if DEBUG
        logger.info("Development mode: load secrets from Keychain, Secrets.plist, or environment variables.")
        #else
        logger.info("Production mode: load secrets from Keychain.")
        #endif
    }
}
