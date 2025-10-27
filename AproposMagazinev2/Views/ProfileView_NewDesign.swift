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
    @ObservedObject private var themeManager = ThemeManager.shared
    
    // State for settings
    @State private var pushNotificationsEnabled = true
    @State private var emailUpdatesEnabled = false
    @State private var showReadingHistory = false
    @State private var showSavedArticles = false
    @State private var showReadingTime = false
    @State private var showDarkModeOptions = false
    @State private var showCacheOptions = false
    @State private var showHelpSupport = false
    @State private var showContactUs = false
    
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
                    Button(action: {
                        showReadingHistory = true
                    }) {
                        SettingsRow(icon: "book.fill", title: "Reading History", subtitle: "View your reading history")
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: {
                        showSavedArticles = true
                    }) {
                        SettingsRow(icon: "bookmark.fill", title: "Saved Articles", subtitle: "\(viewModel.favorites.count) articles")
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: {
                        showReadingTime = true
                    }) {
                        SettingsRow(icon: "clock.fill", title: "Reading Time", subtitle: "Track your reading habits")
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Notifications
                Section("Notifications") {
                    ToggleRow(icon: "bell.fill", title: "Push Notifications", isOn: $pushNotificationsEnabled)
                    ToggleRow(icon: "envelope.fill", title: "Email Updates", isOn: $emailUpdatesEnabled)
                }
                
                // App Settings
                Section("App") {
                    Button(action: {
                        showDarkModeOptions = true
                    }) {
                        SettingsRow(icon: themeManager.currentTheme.icon, title: "Theme", subtitle: themeManager.currentTheme.displayName)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    SettingsRow(icon: "wifi", title: "Offline Reading", subtitle: offlineManager.isOnline ? "Online" : "Offline")
                    
                    Button(action: {
                        showCacheOptions = true
                    }) {
                        SettingsRow(icon: "trash.fill", title: "Clear Cache", subtitle: "Free up space")
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Support
                Section("Support") {
                    Button(action: {
                        showHelpSupport = true
                    }) {
                        SettingsRow(icon: "questionmark.circle.fill", title: "Help & Support")
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: {
                        // Open App Store rating
                        if let url = URL(string: "https://apps.apple.com/app/id123456789") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        SettingsRow(icon: "star.fill", title: "Rate App")
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: {
                        showContactUs = true
                    }) {
                        SettingsRow(icon: "envelope.fill", title: "Contact Us")
                    }
                    .buttonStyle(PlainButtonStyle())
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
        .sheet(isPresented: $showReadingHistory) {
            ReadingHistoryView()
        }
        .sheet(isPresented: $showSavedArticles) {
            NavigationView {
                FavoritesView()
                    .environmentObject(viewModel)
            }
        }
        .sheet(isPresented: $showReadingTime) {
            ReadingTimeView()
        }
        .sheet(isPresented: $showDarkModeOptions) {
            DarkModeOptionsView()
        }
        .sheet(isPresented: $showCacheOptions) {
            CacheOptionsView()
        }
        .sheet(isPresented: $showHelpSupport) {
            HelpSupportView()
        }
        .sheet(isPresented: $showContactUs) {
            ContactUsView()
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

// MARK: - Settings Detail Views
struct ReadingHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section("Recent Articles") {
                    ForEach(0..<5) { index in
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading) {
                                Text("Article \(index + 1)")
                                    .font(.headline)
                                Text("Read 2 hours ago")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Reading History")
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

struct ReadingTimeView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("📚")
                        .font(.system(size: 60))
                    Text("Reading Statistics")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                
                VStack(spacing: 16) {
                    ReadingStatCard(title: "Total Reading Time", value: "24h 32m", icon: "clock.fill")
                    ReadingStatCard(title: "Articles Read", value: "47", icon: "book.fill")
                    ReadingStatCard(title: "Average per Article", value: "31m", icon: "timer")
                    ReadingStatCard(title: "This Week", value: "8h 15m", icon: "calendar")
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Reading Time")
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

struct ReadingStatCard: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .font(.title2)
                .frame(width: 30)
            
            VStack(alignment: .leading) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct DarkModeOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var themeManager = ThemeManager.shared
    
    var body: some View {
        NavigationView {
            List {
                ForEach(AppTheme.allCases, id: \.self) { theme in
                    Button(action: {
                        themeManager.setTheme(theme)
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: theme.icon)
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            
                            Text(theme.displayName)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            if themeManager.currentTheme == theme {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .navigationTitle("Theme")
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

struct CacheOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var cacheSize = "45.2 MB"
    @State private var isClearing = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("🗂️")
                        .font(.system(size: 60))
                    Text("Cache Management")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                
                VStack(spacing: 16) {
                    HStack {
                        Text("Cache Size:")
                            .font(.headline)
                        Spacer()
                        Text(cacheSize)
                            .font(.headline)
                            .foregroundColor(.blue)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    Button(action: {
                        clearCache()
                    }) {
                        HStack {
                            if isClearing {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "trash.fill")
                            }
                            Text(isClearing ? "Clearing..." : "Clear Cache")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isClearing)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Cache Options")
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
    
    private func clearCache() {
        isClearing = true
        // Simulate cache clearing
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            cacheSize = "0 MB"
            isClearing = false
        }
    }
}

struct HelpSupportView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section("Frequently Asked Questions") {
                    HelpRow(title: "How do I save articles?", subtitle: "Tap the bookmark icon on any article")
                    HelpRow(title: "Can I read offline?", subtitle: "Yes, saved articles are available offline")
                    HelpRow(title: "How do I change notifications?", subtitle: "Go to Settings > Notifications")
                }
                
                Section("Contact Support") {
                    Button(action: {
                        if let url = URL(string: "mailto:support@aproposmagazine.com") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        HelpRow(title: "Email Support", subtitle: "support@aproposmagazine.com")
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .navigationTitle("Help & Support")
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

struct HelpRow: View {
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct ContactUsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var isSending = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("📧")
                        .font(.system(size: 60))
                    Text("Contact Us")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Send us a message:")
                        .font(.headline)
                    
                    TextEditor(text: $message)
                        .frame(height: 120)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
                
                Button(action: {
                    sendMessage()
                }) {
                    HStack {
                        if isSending {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                        Text(isSending ? "Sending..." : "Send Message")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(message.isEmpty ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(message.isEmpty || isSending)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Contact Us")
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
    
    private func sendMessage() {
        isSending = true
        // Simulate sending
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isSending = false
            message = ""
            dismiss()
        }
    }
}

// MARK: - Preview
#Preview {
    NavigationView {
        ProfileView_NewDesign()
            .environmentObject(ArticleViewModel())
    }
}
