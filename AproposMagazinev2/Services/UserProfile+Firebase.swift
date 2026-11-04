import Foundation
import FirebaseAuth

extension UserProfile {
    init(firebaseUser: User) {
        self.uid = firebaseUser.uid
        self.email = firebaseUser.email ?? ""
        self.displayName = firebaseUser.displayName ?? ""
        self.photoURL = firebaseUser.photoURL?.absoluteString
        
        // Validate dates once during initialization to prevent timestamp crashes
        let now = Date()
        
        if let creationDate = firebaseUser.metadata.creationDate,
           creationDate.timeIntervalSince1970 > 0 {
            self.createdAt = creationDate
        } else {
            self.createdAt = now
        }
        
        if let lastSignInDate = firebaseUser.metadata.lastSignInDate,
           lastSignInDate.timeIntervalSince1970 > 0 {
            self.lastLoginAt = lastSignInDate
        } else {
            self.lastLoginAt = now
        }
    }
}
