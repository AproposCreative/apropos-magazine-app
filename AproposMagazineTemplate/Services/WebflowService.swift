import Foundation

class WebflowService {
    static let shared = WebflowService()
    private init() {}
    
    struct WebflowResponse: Codable {
        let items: [WebflowItem]
    }
    
    struct WebflowItem: Codable {
        let id: String
        let fieldData: WebflowArticle
    }
    
    struct WebflowArticle: Codable {
        let name: String
        let intro: String?
        let content: String?
        let stjerner: String?

        enum CodingKeys: String, CodingKey {
            case name
            case intro
            case content
            case stjerner
        }
    }
    
    func fetchArticles(completion: @escaping ([Article]) -> Void) {
        let urlString = "https://api.webflow.com/v2/collections/67dbf17ba540975b5b21c2a6/items"
        guard let url = URL(string: urlString) else {
            print("❌ Invalid URL")
            DispatchQueue.main.async { completion([]) }
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer 81734a0b8bd3e2352d9325258ad958eea1626c447113661c97d13b5d3b12efa1", forHTTPHeaderField: "Authorization")
        request.setValue("1.0.0", forHTTPHeaderField: "accept-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Network error: \(error)")
                DispatchQueue.main.async { completion([]) }
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 HTTP Status: \(httpResponse.statusCode)")
                if httpResponse.statusCode != 200 {
                    print("❌ HTTP Error: \(httpResponse.statusCode)")
                }
            }
            
            guard let data = data else {
                print("❌ No data received")
                DispatchQueue.main.async { completion([]) }
                return
            }
            
            // Debug: Print raw JSON response
            if let jsonString = String(data: data, encoding: .utf8) {
                print("📄 Raw JSON response:")
                print(jsonString)
            }
            
            do {
                let decoded = try JSONDecoder().decode(WebflowResponse.self, from: data)
                print("✅ Successfully decoded \(decoded.items.count) articles")
                
                let articles = decoded.items.map { item in
                    return Article(
                        title: item.fieldData.name,
                        intro: item.fieldData.intro ?? "",
                        content: item.fieldData.content ?? "",
                        imageURL: "", // Tilføj hvis du har billede
                        rating: 0,    // Tilføj hvis du har rating
                        options: item.fieldData.stjerner, // fallback for options
                        stjerner: item.fieldData.stjerner,
                        date: nil
                    )
                }
                DispatchQueue.main.async {
                    completion(articles)
                }
            } catch {
                print("❌ Decoding error: \(error)")
                print("❌ Error details: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion([])
                }
            }
        }
        task.resume()
    }

    // Fetch all 'Stjerner' items and return a dictionary mapping ID to name
    func fetchStjernerLabels(completion: @escaping ([String: String]) -> Void) {
        let stjernerCollectionId = "67dbf17ba540975b5b21c294"
        let urlString = "https://api.webflow.com/v2/collections/\(stjernerCollectionId)/items"
        guard let url = URL(string: urlString) else {
            print("❌ Invalid Stjerner URL")
            DispatchQueue.main.async { completion([:]) }
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer 81734a0b8bd3e2352d9325258ad958eea1626c447113661c97d13b5d3b12efa1", forHTTPHeaderField: "Authorization")
        request.setValue("1.0.0", forHTTPHeaderField: "accept-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Network error (Stjerner): \(error)")
                DispatchQueue.main.async { completion([:]) }
                return
            }
            guard let data = data else {
                print("❌ No data received (Stjerner)")
                DispatchQueue.main.async { completion([:]) }
                return
            }
            // Debug: Print raw JSON response
            if let jsonString = String(data: data, encoding: .utf8) {
                print("📄 Raw Stjerner JSON response:")
                print(jsonString)
            }
            do {
                struct StjernerResponse: Codable {
                    let items: [StjerneItem]
                }
                struct StjerneItem: Codable {
                    let id: String
                    let fieldData: StjerneFieldData
                }
                struct StjerneFieldData: Codable {
                    let name: String
                }
                let decoded = try JSONDecoder().decode(StjernerResponse.self, from: data)
                let dict = Dictionary(uniqueKeysWithValues: decoded.items.map { ($0.id, $0.fieldData.name) })
                DispatchQueue.main.async {
                    completion(dict)
                }
            } catch {
                print("❌ Decoding error (Stjerner): \(error)")
                DispatchQueue.main.async { completion([:]) }
            }
        }
        task.resume()
    }
}
