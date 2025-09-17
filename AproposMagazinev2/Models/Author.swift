import Foundation

struct Author: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let name: String
    let bio: String?
    let imageURL: String?
    let position: String
    let photoURL: String
}
struct AuthorWrapper: Codable {
    let id: String
    let fieldData: FieldData
    
    struct FieldData: Codable {
        let name: String
        let bio: String?
        let position: String
        let photo: Photo?
    }
    
    struct Photo: Codable {
        let url: String?
    }
    
    func toAuthor() -> Author {
        return Author(id: id, name: fieldData.name, bio: fieldData.bio, imageURL: fieldData.photo?.url, position: fieldData.position, photoURL: fieldData.photo?.url ?? ""  )
    }
}

