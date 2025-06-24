import Foundation

class OpenAIManager {
    static let shared = OpenAIManager()
    private init() {}
    
    private let apiKey = "sk-..." // INDSÆT DIN OPENAI API-NØGLE HER
    private let endpoint = "https://api.openai.com/v1/chat/completions"
    
    struct AIArticle: Codable {
        let title: String
        let intro: String
        let content: String
        let imageURL: String
        let rating: Int
    }
    
    func getRecommendations(for readTitles: [String], completion: @escaping ([Article]) -> Void) {
        let prompt = "Du er en kulturredaktør. Giv 3 anbefalinger på artikler (som JSON array) til en bruger, der har læst: \n\(readTitles.joined(separator: ", ")). Hver artikel skal have felterne: title, intro, content, imageURL, rating (1-6). Svar kun med JSON."
        let requestBody: [String: Any] = [
            "model": "gpt-3.5-turbo",
            "messages": [
                ["role": "system", "content": "Du er en hjælpsom kulturredaktør."],
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 800,
            "temperature": 0.8
        ]
        guard let url = URL(string: endpoint),
              let httpBody = try? JSONSerialization.data(withJSONObject: requestBody) else {
            completion([])
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let choices = json?["choices"] as? [[String: Any]],
                      let message = choices.first?["message"] as? [String: Any],
                      let content = message["content"] as? String,
                      let articlesData = content.data(using: .utf8) else {
                    DispatchQueue.main.async { completion([]) }
                    return
                }
                let aiArticles = try JSONDecoder().decode([AIArticle].self, from: articlesData)
                let articles = aiArticles.map { ai in
                    Article(title: ai.title, intro: ai.intro, content: ai.content, imageURL: ai.imageURL, rating: ai.rating)
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
