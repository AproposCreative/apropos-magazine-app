import Foundation
import FirebaseAuth

@MainActor
class AuthService: ObservableObject {
    static let shared = AuthService()
    private init() {}

    @Published var user: User?

    func signUp(email: String, password: String, completion: @escaping (Result<User, Error>) -> Void) {
        Auth.auth().createUser(withEmail: email, password: password) { result, error in
            if let error = error {
                completion(.failure(error))
            } else if let user = result?.user {
                self.user = user
                completion(.success(user))
            }
        }
    }

    func signIn(email: String, password: String, completion: @escaping (Result<User, Error>) -> Void) {
        Auth.auth().signIn(withEmail: email, password: password) { result, error in
            if let error = error {
                completion(.failure(error))
            } else if let user = result?.user {
                self.user = user
                completion(.success(user))
            }
        }
    }

    func signOut() throws {
        try Auth.auth().signOut()
        self.user = nil
    }

    var currentUser: User? {
        Auth.auth().currentUser
    }
} 