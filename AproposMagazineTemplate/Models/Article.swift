import Foundation

struct Article: Identifiable, Codable {
    let id = UUID()
    let title: String
    let intro: String
    let content: String
    let imageURL: String
    let rating: Int
}
