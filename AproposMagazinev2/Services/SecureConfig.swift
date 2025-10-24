import Foundation
import Security

/// Secure configuration manager for API keys and sensitive data
class SecureConfig {
    static let shared = SecureConfig()
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
    
    // MARK: - API Key Getters
    
    var webflowAPIKey: String {
        if let key = getAPIKey(for: "webflow") {
            return key
        }
        
        // Fallback to environment variable for development
        if let envKey = ProcessInfo.processInfo.environment["WEBFLOW_API_KEY"] {
            return envKey
        }
        
        // Last resort - return empty string (will cause API calls to fail)
        print("⚠️ WARNING: No Webflow API key found in keychain or environment variables")
        return ""
    }
    
    var googleAPIKey: String {
        if let key = getAPIKey(for: "google") {
            return key
        }
        
        // Fallback to environment variable for development
        if let envKey = ProcessInfo.processInfo.environment["GOOGLE_API_KEY"] {
            return envKey
        }
        
        // Last resort - return empty string (will cause API calls to fail)
        print("⚠️ WARNING: No Google API key found in keychain or environment variables")
        return ""
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
        // Development setup - you can hardcode keys here temporarily
        // but make sure to remove them before committing
        print("🔧 Development mode: Using environment variables for API keys")
        #else
        // Production setup - keys should be stored in keychain
        print("🔒 Production mode: Using keychain for API keys")
        #endif
    }
}
