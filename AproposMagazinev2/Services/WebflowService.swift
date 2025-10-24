import Foundation
import SwiftUI

private var webflowAPIToken: String {
    // TODO: Replace with secure environment variable or keychain
    return "YOUR_NEW_WEBFLOW_API_KEY_HERE"
}

// The model types (Article, Topic, Author, WebflowSection) should be available
// in the same module/target as this service

class WebflowService {
    static let shared = WebflowService()
    private init() {}
    
    // API Token property for direct access
    var apiToken: String {
        // TODO: Replace with secure environment variable or keychain
        return "YOUR_NEW_WEBFLOW_API_KEY_HERE"
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
    
    func fetchStarsMapping(completion: @escaping ([String: String]) -> Void) {
           
           guard let url = URL(string: "https://api.webflow.com/v2/collections/67dbf17ba540975b5b21c294") else {
               print("Invalid URL")
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
                   print("Error: \(error.localizedDescription)")
                   completion([:])
                   return
               }
               
               if let httpResponse = response as? HTTPURLResponse {
                   print("[WebflowService] Stars HTTP Status Code:", httpResponse.statusCode)
                   if httpResponse.statusCode != 200 {
                       print("[WebflowService] Stars HTTP Error - Status Code:", httpResponse.statusCode)
                       // If we get an error response, return default mapping instead of empty
                       let defaultMapping = [
                           "1": "1 stjerne",
                           "2": "2 stjerner", 
                           "3": "3 stjerner",
                           "4": "4 stjerner",
                           "5": "5 stjerner"
                       ]
                       print("[WebflowService] Using default stars mapping due to HTTP error")
                       completion(defaultMapping)
                       return
                   }
               }
               
               guard let data = data else {
                   print("No data")
                   // Return default mapping if no data
                   let defaultMapping = [
                       "1": "1 stjerne",
                       "2": "2 stjerner", 
                       "3": "3 stjerner",
                       "4": "4 stjerner",
                       "5": "5 stjerner"
                   ]
                   print("[WebflowService] Using default stars mapping due to no data")
                   completion(defaultMapping)
                   return
               }
               
               // Print hele JSON-svaret for at debugge stars data
               if let jsonString = String(data: data, encoding: .utf8) {
                   print("[DEBUG] RAW STARS JSON:\n" + jsonString)
               }
               
               do {
                   let decoded = try JSONDecoder().decode(WebflowCollectionResponse.self, from: data)
                   
                   if let starsField = decoded.fields.first(where: { $0.slug == "stars-1-5" }),
                      let options = starsField.options {
                       
                       let mapping = Dictionary(uniqueKeysWithValues: options.map { ($0.id, $0.label) })
                       print("Stars Mapping: \(mapping)")
                       completion(mapping)
                       
                   } else {
                       print("ℹ️ stars-1-5 field not found in collection - using default mapping")
                       // Return a default mapping if stars field is not found
                       let defaultMapping = [
                           "1": "1 stjerne",
                           "2": "2 stjerner", 
                           "3": "3 stjerner",
                           "4": "4 stjerner",
                           "5": "5 stjerner"
                       ]
                       print("[WebflowService] Using default stars mapping")
                       completion(defaultMapping)
                   }
                   
               } catch {
                   print("Decoding error: \(error.localizedDescription)")
                   print("Stars DecodingError details:", error)
                   if let decodingError = error as? DecodingError {
                       print("Stars DecodingError details:", decodingError)
                   }
                   // Return default mapping instead of crashing
                   let defaultMapping = [
                       "1": "1 stjerne",
                       "2": "2 stjerner", 
                       "3": "3 stjerner",
                       "4": "4 stjerner",
                       "5": "5 stjerner"
                   ]
                   print("[WebflowService] Stars decoding failed, returning default mapping")
                   completion(defaultMapping)
               }
               
           }
        task.resume()
       }
    
    func fetchArticles(completion: @escaping (Result<[Article], Error>) -> Void) {
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
                print("[WebflowService] Network error:", error)
                print("[WebflowService] Network error details:", error.localizedDescription)
                
                // Handle specific network errors
                if let urlError = error as? URLError {
                    switch urlError.code {
                    case .timedOut:
                        print("[WebflowService] Request timed out")
                    case .notConnectedToInternet:
                        print("[WebflowService] No internet connection")
                    case .cannotConnectToHost:
                        print("[WebflowService] Cannot connect to host")
                    default:
                        print("[WebflowService] URL Error: \(urlError.localizedDescription)")
                    }
                }
                
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("[WebflowService] HTTP Status Code:", httpResponse.statusCode)
                if httpResponse.statusCode != 200 {
                    print("[WebflowService] HTTP Error - Status Code:", httpResponse.statusCode)
                }
            }
            
            guard let data = data else {
                let error = NSError(domain: "WebflowService", code: 1, userInfo: [NSLocalizedDescriptionKey: "No data received from server."])
                print("[WebflowService] No data received from server.")
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            
            // Print hele JSON-svaret for at debugge publiceringsfelt
            if let jsonString = String(data: data, encoding: .utf8) {
                print("[DEBUG] RAW ARTICLE JSON:\n" + jsonString)
            }
            
            do {
                let webflowData = try JSONDecoder().decode(WebflowResponse.self, from: data)
                let publishedArticles = webflowData.items.filter { $0.isDraft == false }
                DispatchQueue.main.async {
                    completion(.success(publishedArticles))
                }
            } catch {
                print("[WebflowService] Decoding error:", error)
                print("[WebflowService] Error details:", error.localizedDescription)
                if let decodingError = error as? DecodingError {
                    print("[WebflowService] DecodingError details:", decodingError)
                }
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        task.resume()
    }
    
    func fetchTopics(completion: @escaping (Result<[Topic], Error>) -> Void) {
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
                print("[WebflowService] Topics network error:", error)
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data else {
                let error = NSError(domain: "WebflowService", code: 1, userInfo: [NSLocalizedDescriptionKey: "No data received from server."])
                print("[WebflowService] No data received from server (topics).")
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            do {
                let webflowData = try JSONDecoder().decode(WebflowTopicsResponse.self, from: data)
                DispatchQueue.main.async {
                    completion(.success(webflowData.items))
                }
            } catch {
                print("[WebflowService] Decoding error (topics):", error)
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        task.resume()
    }
    
    func fetchAuthors(completion: @escaping (Result<[Author], Error>) -> Void) {
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
                print("[WebflowService] Sections network error:", error)
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data else {
                let error = NSError(domain: "WebflowService", code: 1, userInfo: [NSLocalizedDescriptionKey: "No data received from server."])
                print("[WebflowService] No data received from server (sections).")
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            do {
                let webflowData = try JSONDecoder().decode(WebflowSectionsResponse.self, from: data)
                DispatchQueue.main.async {
                    completion(.success(webflowData.items))
                }
            } catch {
                print("[WebflowService] Decoding error (sections):", error)
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        task.resume()
    }
}

