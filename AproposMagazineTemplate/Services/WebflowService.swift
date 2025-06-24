import Foundation

class WebflowService {
    static let shared = WebflowService()
    private init() {}
    
    struct WebflowResponse: Codable {
        let items: [WebflowArticle]
    }
    
    struct WebflowArticle: Codable {
        let title: String
        let intro: String
        let content: String
        let rating: Int
        let mainImage: MainImage?
        
        struct MainImage: Codable {
            let asset: Asset?
            struct Asset: Codable {
                let url: String?
            }
        }
    }
    
    func fetchArticles(completion: @escaping ([Article]) -> Void) {
        let urlString = "https://api.webflow.com/v2/collections/67dbf17ba540975b5b21c2a6/items"
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async { completion([]) }
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer 81734a0b8bd3e2352d9325258ad958eea1626c447113661c97d13b5d3b12efa1", forHTTPHeaderField: "Authorization")
        request.setValue("1.0.0", forHTTPHeaderField: "accept-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            do {
                let decoded = try JSONDecoder().decode(WebflowResponse.self, from: data)
                let articles = decoded.items.map { wa in
                    Article(
                        title: wa.title,
                        intro: wa.intro,
                        content: wa.content,
                        imageURL: wa.mainImage?.asset?.url ?? "",
                        rating: wa.rating
                    )
                }
                DispatchQueue.main.async {
                    completion(articles)
                }
            } catch {
                DispatchQueue.main.async {
                    completion([])
                }
            }
        }
        task.resume()
    }
}
