import SwiftUI
import SDWebImageSwiftUI

struct ProfileView: View {
    @EnvironmentObject var viewModel: MovieViewModel
    @StateObject private var userManager = UserManager.shared
    @StateObject private var googleSignIn = GoogleSignInService.shared
    @State private var showLoginSheet = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let user = userManager.currentUser {
                    loggedInContent(user: user)
                } else {
                    loggedOutContent
                }
            }
            .padding()
        }
        .background(Color(hex: "0F0F23"))
        .navigationTitle("Profil")
        .sheet(isPresented: $showLoginSheet) {
            LoginView()
        }
    }
    
    private func loggedInContent(user: UserProfile) -> some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                if let photoURL = user.photoURL, let url = URL(string: photoURL) {
                    WebImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        profilePlaceholder
                    }
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
                } else {
                    profilePlaceholder
                }
                
                Text(user.displayName)
                    .font(.title2.bold())
                    .foregroundColor(.white)
                
                Text(user.email)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            
            VStack(alignment: .leading, spacing: 0) {
                settingsHeader("By")
                
                Button {
                    // City selection is done via the selector
                } label: {
                    settingsRow(icon: "mappin.circle.fill", title: "Foretrukken by", value: user.preferredCity)
                }
            }
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(alignment: .leading, spacing: 0) {
                settingsHeader("Notifikationer")
                
                Toggle(isOn: Binding(
                    get: { user.notificationPreferences.premiereAlerts },
                    set: { newValue in
                        var prefs = user.notificationPreferences
                        prefs.premiereAlerts = newValue
                        userManager.updateNotificationPreferences(prefs)
                    }
                )) {
                    Label("Premiere-påmindelser", systemImage: "bell.badge.fill")
                        .foregroundColor(.white)
                }
                .padding()
                .tint(Color(hex: "6366F1"))
                
                Divider().background(Color.white.opacity(0.1))
                
                Toggle(isOn: Binding(
                    get: { user.notificationPreferences.newMovies },
                    set: { newValue in
                        var prefs = user.notificationPreferences
                        prefs.newMovies = newValue
                        userManager.updateNotificationPreferences(prefs)
                    }
                )) {
                    Label("Nye film i biografen", systemImage: "film.fill")
                        .foregroundColor(.white)
                }
                .padding()
                .tint(Color(hex: "6366F1"))
            }
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(spacing: 0) {
                settingsRow(icon: "number", title: "Film i watchlist", value: "\(viewModel.watchlistMovies.count)")
            }
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            Button {
                googleSignIn.signOut()
            } label: {
                Text("Log ud")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            Text("Gobio.dk v0.1.0")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.3))
        }
    }
    
    private var loggedOutContent: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Image(systemName: "film.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "6366F1"), Color(hex: "818CF8")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("Log ind på Gobio")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                
                Text("Opret en konto for at gemme film til din watchlist og få premiere-notifikationer.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 30)
            
            Button {
                Task {
                    await googleSignIn.signIn()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "g.circle.fill")
                    Text("Fortsæt med Google")
                        .font(.subheadline.bold())
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(hex: "4285F4"))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            Button {
                showLoginSheet = true
            } label: {
                Text("Log ind med email")
                    .font(.subheadline.bold())
                    .foregroundColor(Color(hex: "6366F1"))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(hex: "6366F1").opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    private var profilePlaceholder: some View {
        Circle()
            .fill(Color(hex: "6366F1").opacity(0.3))
            .frame(width: 80, height: 80)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.title)
                    .foregroundColor(.white.opacity(0.6))
            }
    }
    
    private func settingsHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundColor(.white.opacity(0.4))
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }
    
    private func settingsRow(icon: String, title: String, value: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .foregroundColor(.white)
            Spacer()
            Text(value)
                .foregroundColor(.white.opacity(0.5))
        }
        .padding()
    }
}

struct LoginView: View {
    @Environment(\.dismiss) var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var errorMessage: String?
    @State private var isLoading = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(isSignUp ? "Opret konto" : "Log ind")
                    .font(.title.bold())
                    .foregroundColor(.white)
                
                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                    
                    SecureField("Adgangskode", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(isSignUp ? .newPassword : .password)
                }
                
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                
                Button {
                    isLoading = true
                    errorMessage = nil
                    
                    if isSignUp {
                        AuthService.shared.signUp(email: email, password: password) { result in
                            isLoading = false
                            switch result {
                            case .success: dismiss()
                            case .failure(let error): errorMessage = error.localizedDescription
                            }
                        }
                    } else {
                        AuthService.shared.signIn(email: email, password: password) { result in
                            isLoading = false
                            switch result {
                            case .success: dismiss()
                            case .failure(let error): errorMessage = error.localizedDescription
                            }
                        }
                    }
                } label: {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(isSignUp ? "Opret konto" : "Log ind")
                            .font(.subheadline.bold())
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(hex: "6366F1"))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .disabled(isLoading || email.isEmpty || password.isEmpty)
                
                Button {
                    isSignUp.toggle()
                    errorMessage = nil
                } label: {
                    Text(isSignUp ? "Har allerede en konto? Log ind" : "Har du ikke en konto? Opret en")
                        .font(.caption)
                        .foregroundColor(Color(hex: "6366F1"))
                }
                
                Spacer()
            }
            .padding()
            .background(Color(hex: "0F0F23"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuller") { dismiss() }
                }
            }
        }
    }
}
