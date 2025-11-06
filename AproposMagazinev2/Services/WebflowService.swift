import Foundation
import OSLog
import SwiftUI

private var webflowAPIToken: String {
    return SecureConfig.shared.webflowAPIKey
}

// The model types (Article, Topic, Author, WebflowSection) should be available
// in the same module/target as this service

class WebflowService {
    static let shared = WebflowService()
    private init() {}
    
    private let logger = Logger(subsystem: "com.aproposmagazine.app", category: "WebflowService")
    
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
               logger.error("Kan ikke hente stjerner – Webflow API nøgle mangler.")
               completion(Self.defaultStarsMapping)
               return
           }
           
           guard let url = URL(string: "https://api.webflow.com/v2/collections/67dbf17ba540975b5b21c294") else {
               logger.error("Ugyldig URL til stjernemapping.")
               completion([:])
               return
           }
           
           var request = URLRequest(url: url)
           request.httpMethod = "GET"
           request.setValue("Bearer \(webflowAPIToken)", forHTTPHeaderField: "Authorization")
           request.setValue("1.0.0", forHTTPHeaderField: "accept-version")
           request.setValue("application/json", forHTTPHeaderField: "Content-Type")
           
           let task = URLSession.shared.dataTask(with: request) { data, response, error in
               
               if let error = error {
                   logger.error("Fejl ved hentning af stjernemapping: \(error.localizedDescription, privacy: .public)")
                   completion(Self.defaultStarsMapping)
                   return
               }
               
               if let httpResponse = response as? HTTPURLResponse {
                   logger.debug("Stjernemapping HTTP status: \(httpResponse.statusCode, privacy: .public)")
                   if httpResponse.statusCode != 200 {
                       logger.error("Fejlstatus fra Webflow-stjerner: \(httpResponse.statusCode, privacy: .public)")
                       completion(Self.defaultStarsMapping)
                       return
                   }
               }
               
               guard let data = data else {
                   logger.warning("Ingen data modtaget for stjernemapping – bruger defaults.")
                   completion(Self.defaultStarsMapping)
                   return
               }
               
               // Print hele JSON-svaret for at debugge stars data
               // if let jsonString = String(data: data, encoding: .utf8) {
               //     print("[DEBUG] RAW STARS JSON:\n" + jsonString)
               // }
               
               do {
                   let decoded = try JSONDecoder().decode(WebflowCollectionResponse.self, from: data)
                   
                   if let starsField = decoded.fields.first(where: { $0.slug == "stars-1-5" }),
                      let options = starsField.options {
                       
                       let mapping = Dictionary(uniqueKeysWithValues: options.map { ($0.id, $0.label) })
                       logger.debug("Stjernemapping hentet: \(mapping, privacy: .public)")
                       completion(mapping)
                       
                   } else {
                       logger.warning("Feltet 'stars-1-5' blev ikke fundet – bruger default mapping.")
                      completion(Self.defaultStarsMapping)
                  }
                  
              } catch {
                  logger.error("Fejl ved dekodning af stjernemapping: \(error.localizedDescription, privacy: .public)")
                   if let decodingError = error as? DecodingError {
                       logger.debug("Decoding detaljer: \(String(describing: decodingError), privacy: .public)")
                   }
                   completion(Self.defaultStarsMapping)
               }
               
           }
        task.resume()
       }
    
    func fetchArticles(completion: @escaping (Result<[Article], Error>) -> Void) {
        guard !apiToken.isEmpty else {
            logger.error("Kan ikke hente artikler – Webflow API nøgle mangler.")
            DispatchQueue.main.async {
                completion(.failure(WebflowError.missingAPIToken))
            }
            return
        }
        let urlString = "https://api.webflow.com/v2/collections/67dbf17ba540975b5b21c2a6/items"
        
        guard let url = URL(string: urlString) else {
            let error = NSError(domain: "WebflowService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(webflowAPIToken)", forHTTPHeaderField: "Authorization")
        request.setValue("1.0.0", forHTTPHeaderField: "accept-version")
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                self.logger.error("Netværksfejl ved hentning af artikler: \(error.localizedDescription, privacy: .public)")
                
                if let urlError = error as? URLError {
                    switch urlError.code {
                    case .timedOut:
                        self.logger.error("Webflow forespørgsel timed out.")
                    case .notConnectedToInternet:
                        self.logger.error("Ingen internetforbindelse.")
                    case .cannotConnectToHost:
                        self.logger.error("Kan ikke forbinde til Webflow-host.")
                    default:
                        self.logger.error("URL-fejl: \(urlError.localizedDescription, privacy: .public)")
                    }
                }
                
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                self.logger.debug("Webflow artikler status: \(httpResponse.statusCode, privacy: .public)")
                if httpResponse.statusCode != 200 {
                    self.logger.error("HTTP-fejl ved artikler: \(httpResponse.statusCode, privacy: .public)")
                }
            }
            
            guard let data = data else {
                let error = NSError(domain: "WebflowService", code: 1, userInfo: [NSLocalizedDescriptionKey: "No data received from server."])
                self.logger.error("Ingen data modtaget fra Webflow (artikler).")
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            
            // Print hele JSON-svaret for at debugge publiceringsfelt
            // if let jsonString = String(data: data, encoding: .utf8) {
            //     print("[DEBUG] RAW ARTICLE JSON:\n" + jsonString)
            // }
            
            do {
                let webflowData = try JSONDecoder().decode(WebflowResponse.self, from: data)
                let publishedArticles = webflowData.items.filter { $0.isDraft == false }
                DispatchQueue.main.async {
                    completion(.success(publishedArticles))
                }
            } catch {
                self.logger.error("Fejl ved dekodning af artikler: \(error.localizedDescription, privacy: .public)")
                if let decodingError = error as? DecodingError {
                    self.logger.debug("Decode detaljer: \(String(describing: decodingError), privacy: .public)")
                }
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        task.resume()
    }
    
    func fetchTopics(completion: @escaping (Result<[Topic], Error>) -> Void) {
        guard !apiToken.isEmpty else {
            logger.error("Kan ikke hente emner – Webflow API nøgle mangler.")
            DispatchQueue.main.async {
                completion(.failure(WebflowError.missingAPIToken))
            }
            return
        }
        let urlString = "https://api.webflow.com/v2/collections/67dbf17ba540975b5b21c2af/items"
        guard let url = URL(string: urlString) else {
            let error = NSError(domain: "WebflowService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(webflowAPIToken)", forHTTPHeaderField: "Authorization")
        request.setValue("1.0.0", forHTTPHeaderField: "accept-version")
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                self.logger.error("Netværksfejl ved hentning af emner: \(error.localizedDescription, privacy: .public)")
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data else {
                let error = NSError(domain: "WebflowService", code: 1, userInfo: [NSLocalizedDescriptionKey: "No data received from server."])
                self.logger.error("Ingen data modtaget fra Webflow (emner).")
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            do {
                let webflowData = try JSONDecoder().decode(WebflowTopicsResponse.self, from: data)
                DispatchQueue.main.async {
                    completion(.success(webflowData.items))
                }
            } catch {
                self.logger.error("Fejl ved dekodning af emner: \(error.localizedDescription, privacy: .public)")
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        task.resume()
    }
    
    func fetchAuthors(completion: @escaping (Result<[Author], Error>) -> Void) {
        guard !apiToken.isEmpty else {
            logger.error("Kan ikke hente forfattere – Webflow API nøgle mangler.")
            DispatchQueue.main.async {
                completion(.failure(WebflowError.missingAPIToken))
            }
            return
        }
        let collectionId = "67dbf17ba540975b5b21c294"
        guard let url = URL(string: "https://api.webflow.com/v2/collections/\(collectionId)/items?live=true") else {
            DispatchQueue.main.async {
                completion(.failure(NSError(domain: "WebflowService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ugyldig URL"])))
            }
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(webflowAPIToken)", forHTTPHeaderField: "Authorization")
        request.setValue("1.0.0", forHTTPHeaderField: "accept-version")
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "WebflowService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Ingen data"])))
                }
                return
            }
            do {
                let decoded = try JSONDecoder().decode(WebflowAuthorsResponse.self, from: data)
                let authors = decoded.items.map { $0.toAuthor() }
                DispatchQueue.main.async {
                    completion(.success(authors))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
        task.resume()
    }
    
    func fetchSections(completion: @escaping (Result<[WebflowSection], Error>) -> Void) {
        guard !apiToken.isEmpty else {
            logger.error("Kan ikke hente sektioner – Webflow API nøgle mangler.")
            DispatchQueue.main.async {
                completion(.failure(WebflowError.missingAPIToken))
            }
            return
        }
        let urlString = "https://api.webflow.com/v2/collections/67dbf17ba540975b5b21c2ae/items"
        guard let url = URL(string: urlString) else {
            let error = NSError(domain: "WebflowService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            DispatchQueue.main.async { completion(Result<[WebflowSection], Error>.failure(error)) }
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(webflowAPIToken)", forHTTPHeaderField: "Authorization")
        request.setValue("1.0.0", forHTTPHeaderField: "accept-version")
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                self.logger.error("Netværksfejl ved hentning af sektioner: \(error.localizedDescription, privacy: .public)")
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data else {
                let error = NSError(domain: "WebflowService", code: 1, userInfo: [NSLocalizedDescriptionKey: "No data received from server."])
                self.logger.error("Ingen data modtaget fra Webflow (sektioner).")
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            do {
                let webflowData = try JSONDecoder().decode(WebflowSectionsResponse.self, from: data)
                DispatchQueue.main.async {
                    completion(.success(webflowData.items))
                }
            } catch {
                self.logger.error("Fejl ved dekodning af sektioner: \(error.localizedDescription, privacy: .public)")
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        task.resume()
    }
}
