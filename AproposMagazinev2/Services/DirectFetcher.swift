import Foundation

class DirectFetcher {
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
        
        let token = SecureConfig.shared.webflowAPIKey
        guard !token.isEmpty else {
            completion("Manglende API-token.")
            return
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
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
