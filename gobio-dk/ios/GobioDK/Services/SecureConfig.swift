import Foundation
import OSLog
import Security

class SecureConfig {
    static let shared = SecureConfig()
    
    private let logger = Logger(subsystem: "dk.gobio.app", category: "SecureConfig")
    private let secrets: [String: Any] = SecureConfig.loadSecrets()
    
    private init() {}
    
    var tmdbAPIKey: String? {
        if let key = getAPIKey(for: "dk.gobio.tmdb") {
            return key
        }
        if let key = secrets["TMDB_API_KEY"] as? String, !key.isEmpty {
            return key
        }
        if let key = ProcessInfo.processInfo.environment["TMDB_API_KEY"] {
            return key
        }
        logger.warning("TMDB API-nøgle ikke fundet")
        return nil
    }
    
    func storeAPIKey(_ key: String, for service: String) -> Bool {
        let data = key.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "api_key",
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
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
    
    private static func loadSecrets() -> [String: Any] {
        if let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
           let data = try? Data(contentsOf: url),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            return plist
        }
        return [:]
    }
}
