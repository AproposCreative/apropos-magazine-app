//
//  ProfileView_NewDesign.swift
//  AproposMagazinev2
//
//  New Instagram-style profile design
//  Based on DetailsPro design
//

import SwiftUI

struct ProfileView_NewDesign: View {
    @EnvironmentObject var viewModel: ArticleViewModel
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject private var userManager = UserManager.shared
    
    // User profile data
    @State private var userName = "Apropos Reader"
    @State private var userBio = "Exploring culture, music, and art through Apropos Magazine 📚"
    @State private var userWebsite = "aproposmagazine.com"
    @State private var showSettings = false
    
    // Stats
    private var readArticlesCount: Int {
        // Count articles that have been read (you can implement this logic)
        return viewModel.articles.count // For now, using total articles
    }
    
    private var favoriteArticlesCount: Int {
        return viewModel.favorites.count
    }
    
    private var totalArticlesCount: Int {
        return viewModel.articles.count
    }
    
    var body: some View {
        ScrollView {
            VStack {
                // Header with username and settings
                HStack {
                    Text(userManager.currentUser?.displayName ?? userName)
                        .font(.system(.headline, weight: .medium))
                    
                    Spacer()
                    
                    Button(action: {
                        showSettings = true
                    }) {
                        Image(systemName: "gearshape")
                            .font(.system(.headline, weight: .medium))
                    }
                }
                .padding(.horizontal)
                
                // Profile Picture
                AsyncImage(url: URL(string: userManager.currentUser?.photoURL ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 100))
                        .foregroundColor(.blue)
                }
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 67, style: .continuous))
                
                // Stats Row
                HStack(spacing: 4) {
                    VStack {
                        Text("\(totalArticlesCount)")
                            .font(.system(.headline, weight: .semibold))
                        Text("Articles")
                            .font(.footnote)
                    }
                    .frame(width: 80)
                    
                    VStack {
                        Text("\(readArticlesCount)")
                            .font(.system(.headline, weight: .semibold))
                        Text("Read")
                            .font(.footnote)
                    }
                    .frame(width: 80)
                    
                    VStack {
                        Text("\(favoriteArticlesCount)")
                            .font(.system(.headline, weight: .semibold))
                        Text("Saved")
                            .font(.footnote)
                    }
                    .frame(width: 80)
                }
                .padding()
                
                // Bio Section
                VStack(spacing: 4) {
                    Text(userManager.currentUser?.displayName ?? userName)
                        .font(.headline)
                    
                    Text(userBio)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                    
                    Text(userWebsite)
                        .underline()
                        .foregroundStyle(.blue)
                        .font(.subheadline)
                }
                .frame(width: 250)
                
                // Content Type Selector
                HStack {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]) {
                        Image(systemName: "photo")
                            .foregroundStyle(.blue)
                        Image(systemName: "bookmark")
                            .foregroundStyle(.secondary)
                        Image(systemName: "heart")
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.secondary)
                .font(.title2)
                .padding(.top, 40)
                .padding(.bottom, 8)
                .padding(.horizontal, 4)
                
                // Articles Grid
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 1), 
                    GridItem(.flexible(), spacing: 1), 
                    GridItem(.flexible(), spacing: 1)
                ], spacing: 1) {
                    ForEach(Array(viewModel.articles.prefix(9)), id: \.id) { article in
                        NavigationLink(destination: ArticleDetailView(article: article).environmentObject(viewModel)) {
                            ArticleThumbnailView(article: article)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
            .padding(.bottom, 100)
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}

// MARK: - Article Thumbnail View
struct ArticleThumbnailView: View {
    let article: Article
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        var mutableArticle = article
        let thumbnailURL = mutableArticle.thumbnailURL
        
        AsyncImage(url: URL(string: thumbnailURL)) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .overlay(
                    Image(systemName: "photo")
                        .foregroundColor(.gray)
                        .font(.title2)
                )
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .aspectRatio(1/1, contentMode: .fit)
        .clipped()
        .overlay(
            // Add a subtle overlay to indicate it's clickable
            Rectangle()
                .fill(Color.black.opacity(0.1))
                .opacity(0)
        )
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var viewModel: ArticleViewModel
    @ObservedObject private var userManager = UserManager.shared
    @ObservedObject private var notificationService = NotificationService.shared
    @ObservedObject private var offlineManager = OfflineManager.shared
    
    var body: some View {
        NavigationView {
            List {
                // Account Section
                Section {
                    HStack {
                        AsyncImage(url: URL(string: userManager.currentUser?.photoURL ?? "")) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.blue)
                        }
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                        
                        VStack(alignment: .leading) {
                            Text(userManager.currentUser?.displayName ?? "User")
                                .font(.headline)
                            Text(userManager.currentUser?.email ?? "")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                
                // Reading Settings
                Section("Reading") {
                    SettingsRow(icon: "book.fill", title: "Reading History", subtitle: "View your reading history")
                    SettingsRow(icon: "bookmark.fill", title: "Saved Articles", subtitle: "\(viewModel.favorites.count) articles")
                    SettingsRow(icon: "clock.fill", title: "Reading Time", subtitle: "Track your reading habits")
                }
                
                // Notifications
                Section("Notifications") {
                    ToggleRow(icon: "bell.fill", title: "Push Notifications", isOn: .constant(true))
                    ToggleRow(icon: "envelope.fill", title: "Email Updates", isOn: .constant(false))
                }
                
                // App Settings
                Section("App") {
                    SettingsRow(icon: "moon.fill", title: "Dark Mode", subtitle: "System")
                    SettingsRow(icon: "wifi", title: "Offline Reading", subtitle: offlineManager.isOnline ? "Online" : "Offline")
                    SettingsRow(icon: "trash.fill", title: "Clear Cache", subtitle: "Free up space")
                }
                
                // Support
                Section("Support") {
                    SettingsRow(icon: "questionmark.circle.fill", title: "Help & Support")
                    SettingsRow(icon: "star.fill", title: "Rate App")
                    SettingsRow(icon: "envelope.fill", title: "Contact Us")
                }
                
                // Account Actions
                Section {
                    Button(action: {
                        // Sign out action
                        do {
                            try AuthService.shared.signOut()
                            dismiss()
                        } catch {
                            print("Sign out error: \(error)")
                        }
                    }) {
                        HStack {
                            Image(systemName: "arrow.right.square.fill")
                                .foregroundColor(.red)
                            Text("Sign Out")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Settings Row Components
struct SettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String?
    
    init(icon: String, title: String, subtitle: String? = nil) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
    }
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct ToggleRow: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            Text(title)
                .font(.body)
            
            Spacer()
            
            Toggle("", isOn: $isOn)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview
#Preview {
    NavigationView {
        ProfileView_NewDesign()
            .environmentObject(ArticleViewModel())
    }
}
