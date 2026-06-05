import Foundation
import OSLog

class OpenAIManager {
    static let shared = OpenAIManager()
    private init() {}
    
    private let logger = Logger(subsystem: "com.aproposmagazine.app", category: "OpenAIManager")
    private let endpoint = "https://api.openai.com/v1/chat/completions"
    
    struct AIArticle: Codable {
        let title: String
        let intro: String
        let content: String
        let imageURL: String
        let rating: Int
    }
    
    func getRecommendations(for readTitles: [String], completion: @escaping ([Article]) -> Void) {
        let apiKey = SecureConfig.shared.openAIAPIKey
        guard !apiKey.isEmpty else {
            logger.error("Cannot fetch AI recommendations – OpenAI API key mangler.")
            DispatchQueue.main.async { completion([]) }
            return
        }
        
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
                    Article(
                        id: UUID().uuidString,
                        name: ai.title,
                        slug: ai.title.lowercased().replacingOccurrences(of: " ", with: "-"),
                        content: ai.content,
                        intro: ai.intro,
                        stjerne: ai.rating,
                        topicID: "",
                        topicsIDs: nil,
                        authorID: nil,
                        thumbURL: URL(string: ai.imageURL),
                        coverURL: URL(string: ai.imageURL),
                        location: nil,
                        subtitle: nil,
                        isDraft: false
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

    struct RecommendationReasonPayload: Codable {
        let articleId: String
        let reason: String
    }

    func generateRecommendationReasons(
        topTopics: [String],
        candidates: [(id: String, title: String, topics: [String])],
        completion: @escaping ([String: String]) -> Void
    ) {
        let apiKey = SecureConfig.shared.openAIAPIKey
        guard !apiKey.isEmpty, !candidates.isEmpty else {
            DispatchQueue.main.async { completion([:]) }
            return
        }

        let candidateLines = candidates.map { candidate in
            "- id: \(candidate.id), title: \(candidate.title), topics: \(candidate.topics.joined(separator: ", "))"
        }.joined(separator: "\n")

        let prompt = """
        Du er redaktør på Apropos Magazine. Skriv én kort dansk sætning per artikel (max 12 ord) der forklarer hvorfor den anbefales.
        Brugerens top-emner: \(topTopics.joined(separator: ", "))
        Kandidater:
        \(candidateLines)
        Svar KUN med JSON array: [{"articleId":"...","reason":"..."}]
        """

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": "Du svarer kun med valid JSON."],
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 600,
            "temperature": 0.6
        ]

        guard let url = URL(string: endpoint),
              let httpBody = try? JSONSerialization.data(withJSONObject: requestBody) else {
            completion([:])
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data, error == nil else {
                DispatchQueue.main.async { completion([:]) }
                return
            }

            let mapped = Self.parseRecommendationReasons(from: data)
            DispatchQueue.main.async { completion(mapped) }
        }.resume()
    }

    private static func parseRecommendationReasons(from data: Data) -> [String: String] {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            return [:]
        }

        let trimmed = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")

        guard let payloadData = trimmed.data(using: .utf8),
              let reasons = try? JSONDecoder().decode([RecommendationReasonPayload].self, from: payloadData) else {
            return [:]
        }

        return Dictionary(uniqueKeysWithValues: reasons.map { ($0.articleId, $0.reason) })
    }
}
