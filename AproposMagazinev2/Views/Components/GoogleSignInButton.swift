import SwiftUI
import GoogleSignIn

struct GoogleSignInButton: View {
    @ObservedObject private var signInService = GoogleSignInService.shared
    @State private var isLoading = false
    
    var body: some View {
        Button(action: {
            Task {
                isLoading = true
                await signInService.signIn()
                isLoading = false
            }
        }) {
            HStack(spacing: 12) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        .scaleEffect(0.8)
                }
                
                Text("Sign in with Google")
                    .font(.headline)
                    .foregroundColor(.black)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.white)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        }
        .disabled(isLoading)
    }
}

struct GoogleSignOutButton: View {
    @ObservedObject private var signInService = GoogleSignInService.shared
    
    var body: some View {
        Button(action: {
            signInService.signOut()
        }) {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.title2)
                    .foregroundColor(.white)
                
                Text("Sign Out")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.red)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.red.opacity(0.3), lineWidth: 1)
            )
        }
    }
}
