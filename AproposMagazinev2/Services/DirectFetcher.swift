import Foundation

class DirectFetcher {
    // Load Webflow API token from Secrets.plist
    private static var webflowAPIToken: String? = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let token = plist["webflowAPIToken"] as? String else {
            return nil
        }
        return token
    }()
    
    // Current URLSessionDataTask to allow cancellation of previous requests
    var currentTask: URLSessionDataTask?
    
    func fetchData(completion: @escaping (String) -> Void) {
        // Cancel any existing task before starting a new one
        currentTask?.cancel()
        
        let urlString = "https://api.webflow.com/v2/collections/67dbf17ba540975b5b21c2a6/items"
        guard let url = URL(string: urlString) else {
            completion("Ugyldig URL.")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // Set authorization header using the token loaded from Secrets.plist
        if let token = DirectFetcher.webflowAPIToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            completion("Manglende API-token.")
            return
        }
        
        request.setValue("1.0.0", forHTTPHeaderField: "accept-version")

        // Start the data task and assign it to currentTask for potential cancellation
        currentTask = URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion("Netværksfejl:\n\(error.localizedDescription)")
                    return
                }
                guard let data = data else {
                    completion("Ingen data modtaget.")
                    return
                }
                if let jsonString = String(data: data, encoding: .utf8) {
                    completion(jsonString)
                } else {
                    completion("Kunne ikke konvertere data til tekst.")
                }
            }
        }
        currentTask?.resume()
    }
} 
