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
        return viewModel.visibleArticles.count // For now, using total articles
    }
    
    private var favoriteArticlesCount: Int {
        return viewModel.favorites.count
    }
    
    private var totalArticlesCount: Int {
        return viewModel.visibleArticles.count
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
                    ForEach(Array(viewModel.visibleArticles.prefix(9)), id: \.id) { article in
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
    @ObservedObject private var notificationService: NotificationService
    @ObservedObject private var offlineManager = OfflineManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var contentPreferences = PreferencesManager.shared
    
    // State for settings
    @State private var notificationPreferences = NotificationPreferences()
    @State private var selectedNotificationCategoryIds: Set<String> = []
    @State private var profileFormAdoption = UserProfileFormAdoption()
    @State private var showDarkModeOptions = false
    @State private var showHelpSupport = false
    @State private var showContactUs = false
    @State private var showLogoutError = false
    @State private var showLoginSheet = false
    @State private var replayIntroduction = false
    @State private var showPaywall = false
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared

    init(notificationService: NotificationService = .shared) {
        _notificationService = ObservedObject(wrappedValue: notificationService)
    }
    
    private var articleNotificationsEnabled: Bool {
        notificationService.articleNotificationsEnabled(
            preferences: notificationPreferences,
            selectedCategoryIds: Array(selectedNotificationCategoryIds)
        )
    }
    
    var body: some View {
        NavigationView {
            List {
                SettingsAccountSection(snapshot: userManager.profileSnapshot) {
                    showLoginSheet = true
                } onRetry: {
                    if userManager.profileSnapshot.writeReady, let profile = userManager.currentUser {
                        userManager.saveUserProfile(profile)
                    } else {
                        userManager.retryProfileLoad()
                    }
                }

                ContentLanguageSection(preferences: contentPreferences)

                // Notifications
                Section {
                    Toggle(isOn: Binding(
                        get: { articleNotificationsEnabled },
                        set: { isEnabled in
                            if isEnabled {
                                if selectedNotificationCategoryIds.isEmpty {
                                    notificationPreferences.newArticles = true
                                }
                            } else {
                                notificationPreferences.newArticles = false
                                selectedNotificationCategoryIds.removeAll()
                            }
                            saveNotificationChoices()
                        }
                    )) {
                        Text("Artikel-notifikationer")
                    }

                    if articleNotificationsEnabled {
                        Toggle(isOn: Binding(
                            get: { notificationPreferences.newArticles && selectedNotificationCategoryIds.isEmpty },
                            set: { isEnabled in
                                notificationPreferences.newArticles = isEnabled
                                if isEnabled {
                                    selectedNotificationCategoryIds.removeAll()
                                }
                                saveNotificationChoices()
                            }
                        )) {
                            Text("Alle nye artikler")
                        }

                        if !viewModel.topics.isEmpty {
                            ForEach(viewModel.topics.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { topic in
                                Toggle(isOn: Binding(
                                    get: { selectedNotificationCategoryIds.contains(topic.id) },
                                    set: { isEnabled in
                                        if isEnabled {
                                            selectedNotificationCategoryIds.insert(topic.id)
                                            notificationPreferences.newArticles = false
                                        } else {
                                            selectedNotificationCategoryIds.remove(topic.id)
                                        }
                                        saveNotificationChoices()
                                    }
                                )) {
                                    LocalizedArticleTaxonomy(topic.name)
                                }
                            }
                        } else {
                            Text("Emner indlæses...")
                                .foregroundColor(.secondary)
                        }

                        Toggle(isOn: Binding(
                            get: { notificationPreferences.newPodcasts },
                            set: { isEnabled in
                                notificationPreferences.newPodcasts = isEnabled
                                saveNotificationChoices()
                            }
                        )) {
                            Text("Nye podcasts")
                        }

                        Text("Vælg alle nye artikler, eller kun specifikke emner.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Du modtager ikke push, når nye artikler publiceres.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Toggle(isOn: Binding(
                            get: { notificationPreferences.newPodcasts },
                            set: { isEnabled in
                                notificationPreferences.newPodcasts = isEnabled
                                saveNotificationChoices()
                            }
                        )) {
                            Text("Nye podcasts")
                        }
                    }

                    Button {
                        Task {
                            await notificationService.sendTestLocalNotificationAfterAuthorization(delay: 2)
                        }
                    } label: {
                        Label("Test lokal notifikation", systemImage: "bell.badge")
                    }
                    Text("Viser en test på denne enhed. Tester ikke levering via Apple push.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Notifikationer & emner")
                }
                .disabled(userManager.profileSnapshot.context == .unresolved ||
                          (userManager.profileSnapshot.context.userID != nil && !userManager.profileSnapshot.writeReady))
                
                if FeatureFlags.subscriptionsEnabled {
                    Section("Abonnement") {
                        Button {
                            showPaywall = true
                        } label: {
                            SettingsRow(
                                icon: "crown.fill",
                                title: subscriptionManager.isSubscribed ? "Apropos Premium" : "Bliv abonnent",
                                subtitle: subscriptionManager.isSubscribed ? "Aktivt abonnement" : "Få fuld adgang til artikler"
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                
                // App Settings
                Section("App") {
                    Button { replayIntroduction = true } label: {
                        SettingsRow(icon: "sparkles", title: "Vis introduktion")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.showIntroduction")

                    Button(action: {
                        showDarkModeOptions = true
                    }) {
                        SettingsRow(icon: themeManager.currentTheme.icon, title: "Tema", subtitle: themeManager.currentTheme.displayName)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    SettingsRow(icon: "wifi", title: "Offline læsning", subtitle: offlineManager.isOnline ? "Online" : "Offline")
                }
                
                TelemetryPrivacySection(controller: TelemetryRuntime.shared.controller)

                // Support
                Section("Support") {
                    Button(action: {
                        showHelpSupport = true
                    }) {
                        SettingsRow(icon: "questionmark.circle.fill", title: "Hjælp og support")
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: {
                        showContactUs = true
                    }) {
                        SettingsRow(icon: "envelope.fill", title: "Kontakt os")
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Account Actions
                if userManager.currentUser != nil {
                    Section {
                        Button(action: {
                            if GoogleSignInService.shared.signOut() {
                                viewModel.clearSessionDataOnLogout()
                            } else {
                                showLogoutError = true
                            }
                        }) {
                            HStack {
                                Image(systemName: "arrow.right.square.fill")
                                    .foregroundColor(.red)
                                Text("Log ud")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
                SettingsVersionFooter()
            }
            .navigationTitle("Indstillinger")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Færdig") {
                        dismiss()
                    }
                }
            }
        }
        .modifier(ReaderIntroductionPresenter(automatic: false, replayRequested: $replayIntroduction))
        .onReceive(userManager.profileChanges) { snapshot in
            adoptProfileForNotificationForm(snapshot)
        }
        .onAppear {
            adoptProfileForNotificationForm(userManager.profileSnapshot)
            notificationService.refreshAuthorizationStatus()
            queueNotificationChoices()
        }
        .sheet(isPresented: $showDarkModeOptions) {
            DarkModeOptionsView()
        }
        .sheet(isPresented: $showHelpSupport) {
            HelpSupportView()
        }
        .alert("Kunne ikke logge ud", isPresented: $showLogoutError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(LocalizedStringKey(GoogleSignInService.shared.errorMessage ?? "Udlogningen kunne ikke bekræftes. Prøv igen."))
        }
        .sheet(isPresented: $showContactUs) {
            ContactUsView()
        }
        .sheet(isPresented: $showLoginSheet) {
            LoginSheetView(isPresented: $showLoginSheet)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    private func adoptProfileForNotificationForm(_ snapshot: UserProfileState.Snapshot) {
        guard snapshot.generation == userManager.profileSnapshot.generation,
              snapshot.revision == userManager.profileSnapshot.revision,
              profileFormAdoption.shouldAdopt(snapshot, acceptedLoadVersion: userManager.state.acceptedLoadVersion) else { return }
        // Adopt a new owner or a newly accepted profile read. A local save must
        // keep this form's draft while its category persistence is still queued.
        loadNotificationChoices()
    }

    private func loadNotificationChoices() {
        let (preferences, categoryIds) = notificationService.loadPersistedArticleNotificationSettings()
        if let user = userManager.currentUser {
            notificationPreferences = user.notificationPreferences
        } else {
            notificationPreferences = preferences
        }
        selectedNotificationCategoryIds = Set(categoryIds)
    }

    private func queueNotificationChoices() {
        let context = userManager.state.contextTicket()
        guard let apply = userManager.captureNotificationChoices(
            preferences: notificationPreferences, categoryIDs: Array(selectedNotificationCategoryIds),
            allCategoryIDs: viewModel.topics.map(\.id), context: context, service: notificationService
        ) else { return }
        Task { await apply() }
    }

    private func saveNotificationChoices() {
        queueNotificationChoices()
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
                Text(LocalizedStringKey(title))
                    .font(.body)
                if let subtitle = subtitle {
                    Text(LocalizedStringKey(subtitle))
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
            
            Text(LocalizedStringKey(title))
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
            .navigationTitle("Læsehistorik")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Færdig") {
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
                    Text("Læseoverblik")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                
                VStack(spacing: 16) {
                    ReadingStatCard(title: "Samlet læsetid", value: "24t 32m", icon: "clock.fill")
                    ReadingStatCard(title: "Læste artikler", value: "47", icon: "book.fill")
                    ReadingStatCard(title: "Gennemsnit pr. artikel", value: "31m", icon: "timer")
                    ReadingStatCard(title: "Denne uge", value: "8t 15m", icon: "calendar")
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Læsetid")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Færdig") {
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
                Text(LocalizedStringKey(title))
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
                            
                            Text(LocalizedStringKey(theme.displayName))
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
            .navigationTitle("Tema")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Færdig") {
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
                    Text("Cache")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                
                VStack(spacing: 16) {
                    HStack {
                        Text("Cache-størrelse:")
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
                            Text(LocalizedStringKey(isClearing ? "Rydder..." : "Ryd cache"))
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
                    Button("Færdig") {
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
    @State private var showContact = false
    
    var body: some View {
        NavigationView {
            List {
                Section("Ofte stillede spørgsmål") {
                    HelpRow(title: "Hvordan gemmer jeg artikler?", subtitle: "Tryk på bogmærkeikonet på en artikel")
                    HelpRow(title: "Kan jeg læse offline?", subtitle: "Ja, gemte artikler er tilgængelige offline")
                    HelpRow(title: "Hvordan ændrer jeg notifikationer?", subtitle: "Gå til Indstillinger > Notifikationer")
                }
                
                Section("Kontakt") {
                    Button(action: {
                        showContact = true
                    }) {
                        HelpRow(title: "Kontakt os", subtitle: SupportContactPolicy.recipient)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundStyle(.primary)
                    .tint(.primary)
                }
            }
            .navigationTitle("Hjælp og support")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Færdig") {
                        dismiss()
                    }
                    .tint(.primary)
                }
            }
        }
        .sheet(isPresented: $showContact) { ContactUsView() }
    }
}

struct HelpRow: View {
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(title))
                .font(.headline)
            Text(LocalizedStringKey(subtitle))
                .font(.subheadline)
                .foregroundColor(.secondary)
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
