import Foundation

class NetworkManager {
    static let shared = NetworkManager()
    
    private let session: URLSession
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 60.0
        config.waitsForConnectivity = true
        config.allowsCellularAccess = true
        config.httpMaximumConnectionsPerHost = 6
        config.requestCachePolicy = .useProtocolCachePolicy
        
        // Add custom headers. Note: do NOT set Accept-Encoding manually — URLSession
        // adds it automatically and transparently decompresses the response. Setting
        // it by hand disables that automatic decompression and can yield raw/garbled bytes.
        config.httpAdditionalHeaders = [
            "User-Agent": "AproposMagazine-iOS/1.0",
            "Accept": "application/json"
        ]
        
        self.session = URLSession(configuration: config)
    }
    
    func dataTask(with request: URLRequest, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask {
        return session.dataTask(with: request, completionHandler: completionHandler)
    }
    
    func dataTask(with url: URL, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask {
        return session.dataTask(with: url, completionHandler: completionHandler)
    }
}
