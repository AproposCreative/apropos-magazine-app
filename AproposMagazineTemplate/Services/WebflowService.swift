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
        let intro: String
        let content: String
        let stjerner: String?
        let stars_1_5: String?
        // Tilføj evt. flere felter her
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
                    print("DEBUG: stjerner fra fieldData = \(item.fieldData.stjerner ?? "nil") for artikel \(item.fieldData.name)")
                    return Article(
                        title: item.fieldData.name,
                        intro: item.fieldData.intro,
                        content: item.fieldData.content,
                        imageURL: "", // Tilføj hvis du har billede
                        rating: 0,    // Tilføj hvis du har rating
                        options: item.fieldData.stars_1_5, // fallback for options
                        stjerner: item.fieldData.stjerner,
                        stars_1_5: item.fieldData.stars_1_5
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
}
