import Foundation
import SwiftUI

private var webflowAPIToken: String {
    return SecureConfig.shared.webflowAPIKey
}

// The model types (Article, Topic, Author, WebflowSection) should be available
// in the same module/target as this service

class WebflowService {
    static let shared = WebflowService()
    private init() {}

    
    // API Token property for direct access
    var apiToken: String {
        return SecureConfig.shared.webflowAPIKey
    }
    
    enum WebflowError: LocalizedError {
        case missingAPIToken
        
        var errorDescription: String? {
            switch self {
            case .missingAPIToken:
                return "Webflow API nøgle mangler. Tilføj den i Secrets.plist, Keychain eller som environment-variabel."
            }
        }
    }

    struct WebflowResponse: Decodable {
        let items: [Article]
    }

    struct WebflowTopicsResponse: Decodable {
        let items: [Topic]
    }
    
    struct WebflowAuthorsResponse: Decodable {
        let items: [AuthorWrapper]
    }
    
    struct WebflowSectionsResponse: Decodable {
        let items: [WebflowSection]
    }
    
    // Response structure for collection metadata (used in fetchStarsMapping)
    struct WebflowCollectionResponse: Decodable {
        let fields: [WebflowField]
    }
    
    struct WebflowField: Decodable {
        let slug: String
        let options: [WebflowOption]?
    }
    
    struct WebflowOption: Decodable {
        let id: String
        let label: String
    }
    
    private static let defaultStarsMapping: [String: String] = [
        "1": "1 stjerne",
        "2": "2 stjerner",
        "3": "3 stjerner",
        "4": "4 stjerner",
        "5": "5 stjerner"
    ]
    
    func fetchStarsMapping(completion: @escaping ([String: String]) -> Void) {
           
           guard !apiToken.isEmpty else {
               AppDiagnostics.recordOperational(.metadataConfigurationMissing)
               completion(Self.defaultStarsMapping)
               return
           }
           
           guard let url = URL(string: "https://api.webflow.com/v2/collections/67dbf17ba540975b5b21c294") else {
               AppDiagnostics.recordOperational(.metadataURLInvalid)
               completion([:])
               return
           }
           
           var request = URLRequest(url: url)
           request.httpMethod = "GET"
           request.setValue("Bearer \(webflowAPIToken)", forHTTPHeaderField: "Authorization")
           request.setValue("1.0.0", forHTTPHeaderField: "accept-version")
           request.setValue("application/json", forHTTPHeaderField: "Content-Type")
           
           let task = URLSession.shared.dataTask(with: request) { data, response, error in
               
               if error != nil {
                   AppDiagnostics.recordOperational(.metadataFetchFailed)
                   completion(Self.defaultStarsMapping)
                   return
               }
               
               if let httpResponse = response as? HTTPURLResponse {
                   if httpResponse.statusCode != 200 {
                       AppDiagnostics.recordOperational(.metadataRequestRejected)
                       completion(Self.defaultStarsMapping)
                       return
                   }
               }
               
               guard let data = data else {
                   completion(Self.defaultStarsMapping)
                   return
               }
               
               do {
                   let decoded = try JSONDecoder().decode(WebflowCollectionResponse.self, from: data)
                   
                   if let starsField = decoded.fields.first(where: { $0.slug == "stars-1-5" }),
                      let options = starsField.options {
                       
                       let mapping = Dictionary(uniqueKeysWithValues: options.map { ($0.id, $0.label) })
                       completion(mapping)
                       
                   } else {
                      completion(Self.defaultStarsMapping)
                   }
                   
               } catch {
                  AppDiagnostics.recordOperational(.metadataDecodeFailed)
                   completion(Self.defaultStarsMapping)
               }
               
           }
        task.resume()
       }
    
    /// The same validated live-only pagination is used for all local CMS fallbacks.
    private func fetchLiveItems<T: Decodable>(collectionID: String, as type: T.Type,
                                             completion: @escaping (Result<[T], Error>) -> Void) {
        let token = apiToken
        guard !token.isEmpty else {
            DispatchQueue.main.async { completion(.failure(WebflowError.missingAPIToken)) }
            return
        }
        Task {
            do {
                let rows = try await WebflowLiveCatalogLoader().load(collectionID: collectionID, token: token)
                let decoder = JSONDecoder()
                let values = try rows.map { try decoder.decode(T.self, from: $0) }
                DispatchQueue.main.async { completion(.success(values)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func fetchArticles(completion: @escaping (Result<[Article], Error>) -> Void) {
        fetchLiveItems(collectionID: "67dbf17ba540975b5b21c2a6", as: Article.self, completion: completion)
    }

    func fetchTopics(completion: @escaping (Result<[Topic], Error>) -> Void) {
        fetchLiveItems(collectionID: "67dbf17ba540975b5b21c2af", as: Topic.self, completion: completion)
    }

    func fetchAuthors(completion: @escaping (Result<[Author], Error>) -> Void) {
        fetchLiveItems(collectionID: "67dbf17ba540975b5b21c294", as: AuthorWrapper.self) { result in
            completion(result.map { $0.map { $0.toAuthor() } })
        }
    }

    func fetchSections(completion: @escaping (Result<[WebflowSection], Error>) -> Void) {
        fetchLiveItems(collectionID: "67dbf17ba540975b5b21c2ae", as: WebflowSection.self, completion: completion)
    }
}
