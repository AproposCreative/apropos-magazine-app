import SwiftUI
import GoogleSignIn

struct ProfileView: View {
    @ObservedObject private var signInService = GoogleSignInService.shared
    @ObservedObject private var userManager = UserManager.shared
    @ObservedObject private var notificationService = NotificationService.shared
    @ObservedObject private var offlineManager = OfflineManager.shared
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.navigationCoordinator) private var navigationCoordinator
    
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Top padding to account for uniform top bar
                Spacer()
                    .frame(height: 100) // 44 (safe area) + 56 (top bar height)
                
                // Content sections
                VStack(spacing: 0) {
                    // User Profile Section
                    if signInService.isSignedIn, let user = signInService.user {
                        AppleStyleUserProfileSection(user: user)
                        
                        // Reading Statistics Section
                        if userManager.currentUser != nil {
                            AppleStyleReadingStatsSection(stats: userManager.getReadingStats())
                        }
                        
                        // Settings Sections
                        AppleStyleSettingsSections()
                        
                        // Debug Section
                        AppleStyleDebugSection()
                        
                        // Notification Permission Section
                        // AppleStyleNotificationPermissionSection()
                        
                        // Sign Out Section
                        AppleStyleSignOutSection()
                    } else {
                        // Sign In Section
                        AppleStyleSignInSection()
                    }
                    
                    Spacer(minLength: 100)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .uniformTopBar(
            title: "Profil",
            showSearchButton: true,
            showMenuButton: true,
            onSearch: {
                // Navigate to search
                navigationCoordinator.navigateToTab(.search)
            },
            onMenu: {
                // Show settings menu
                print("Settings menu tapped")
            }
        )
            .onAppear {
                // Clear any existing error states
                signInService.clearError()
                
                // Check notification permission status
                UNUserNotificationCenter.current().getNotificationSettings { settings in
                    DispatchQueue.main.async {
                        self.notificationStatus = settings.authorizationStatus
                    }
                }
            }
            .alert("Sign In Error", isPresented: $signInService.showErrorDialog) {
                Button("OK") {
                    signInService.dismissErrorDialog()
                }
            } message: {
                Text(signInService.errorMessage ?? "An unknown error occurred")
            }
        }
    }

// MARK: - Apple Style User Profile Section
struct AppleStyleUserProfileSection: View {
    let user: GIDGoogleUser
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 24) {
                // Profile Image
                AsyncImage(url: user.profile?.imageURL(withDimension: 120)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Color(.systemGray5))
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 40, weight: .light))
                                .foregroundColor(.secondary)
                        )
                }
                .frame(width: 100, height: 100)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
                
                // Name and Email
                VStack(spacing: 4) {
                    Text(user.profile?.name ?? "Ukendt")
                        .font(.system(size: 28, weight: .semibold, design: .default))
                        .foregroundColor(.primary)
                    
                    Text(user.profile?.email ?? "ukendt@email.com")
                        .font(.system(size: 17, weight: .regular, design: .default))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 32)
        }
        .padding(.bottom, 24)
    }
}



// MARK: - Apple Style Reading Stats Section
struct AppleStyleReadingStatsSection: View {
    let stats: ReadingStats
    
    var body: some View {
        VStack(spacing: 0) {
            // Reading Stats Group
            VStack(spacing: 0) {
                AppleStyleListRow(
                    title: "Læsestatistik",
                    icon: "chart.bar",
                    iconColor: .blue,
                    showChevron: true
                )
                
                Divider()
                    .padding(.leading, 44)
                
                AppleStyleListRow(
                    title: "Læste artikler",
                    subtitle: "\(stats.totalArticlesRead)",
                    icon: "book.fill",
                    iconColor: .blue,
                    showChevron: false
                )
                
                Divider()
                    .padding(.leading, 44)
                
                AppleStyleListRow(
                    title: "Bookmarks",
                    subtitle: "\(stats.totalBookmarks)",
                    icon: "bookmark.fill",
                    iconColor: .orange,
                    showChevron: false
                )
                
                Divider()
                    .padding(.leading, 44)
                
                AppleStyleListRow(
                    title: "Favorit kategorier",
                    subtitle: "\(stats.favoriteCategories)",
                    icon: "tag.fill",
                    iconColor: .green,
                    showChevron: false
                )
                
                Divider()
                    .padding(.leading, 44)
                
                AppleStyleListRow(
                    title: "Favorit forfattere",
                    subtitle: "\(stats.favoriteAuthors)",
                    icon: "person.fill",
                    iconColor: .purple,
                    showChevron: false
                )
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 24)
    }
}

// MARK: - Apple Style List Row
struct AppleStyleListRow: View {
    let title: String
    var subtitle: String? = nil
    let icon: String
    let iconColor: Color
    let showChevron: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: 24, height: 24)
            
            // Text
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .regular, design: .default))
                    .foregroundColor(.primary)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 14, weight: .regular, design: .default))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Chevron
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Apple Style Settings Sections
struct AppleStyleSettingsSections: View {
    var body: some View {
        VStack(spacing: 20) {
            // Notification Settings
            AppleStyleNotificationSettingsSection()
            
            // Offline Settings
            AppleStyleOfflineSettingsSection()
        }
        .padding(.horizontal, 20)
    }
}

struct AppleStyleNotificationSettingsSection: View {
    @ObservedObject private var userManager = UserManager.shared
    @ObservedObject private var notificationService = NotificationService.shared
    @State private var preferences: NotificationPreferences = NotificationPreferences()
    
    var body: some View {
        VStack(spacing: 0) {
            // Section Header
            HStack {
                Text("Notifikationer")
                    .font(.system(size: 22, weight: .semibold, design: .default))
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            
            // Notification Toggles
            VStack(spacing: 0) {
                AppleStyleToggleRow(
                    title: "Nye artikler",
                    subtitle: "Få besked om nye artikler",
                    icon: "newspaper",
                    isOn: $preferences.newArticles
                )
                
                Divider()
                    .padding(.leading, 44)
                
                AppleStyleToggleRow(
                    title: "Festival reminders",
                    subtitle: "Påmindelser om kommende festivaler",
                    icon: "calendar",
                    isOn: $preferences.festivalReminders
                )
                
                Divider()
                    .padding(.leading, 44)
                
                AppleStyleToggleRow(
                    title: "Breaking news",
                    subtitle: "Vigtige nyheder og opdateringer",
                    icon: "exclamationmark.triangle",
                    isOn: $preferences.breakingNews
                )
                
                Divider()
                    .padding(.leading, 44)
                
                AppleStyleToggleRow(
                    title: "Ugentlig digest",
                    subtitle: "Ugens bedste artikler hver søndag",
                    icon: "envelope",
                    isOn: $preferences.weeklyDigest
                )
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Quiet Hours
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "moon")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.purple)
                        .frame(width: 24, height: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Stille timer")
                            .font(.system(size: 16, weight: .medium, design: .default))
                            .foregroundColor(.primary)
                        
                        Text("Undgå notifikationer i bestemte timer")
                            .font(.system(size: 14, weight: .regular, design: .default))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: $preferences.quietHours.enabled)
                        .labelsHidden()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                if preferences.quietHours.enabled {
                    Divider()
                        .padding(.leading, 44)
                    
                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Fra")
                                .font(.system(size: 12, weight: .medium, design: .default))
                                .foregroundColor(.secondary)
                            
                            DatePicker("", selection: $preferences.quietHours.startTime, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .scaleEffect(0.9)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Til")
                                .font(.system(size: 12, weight: .medium, design: .default))
                                .foregroundColor(.secondary)
                            
                            DatePicker("", selection: $preferences.quietHours.endTime, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .scaleEffect(0.9)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .onAppear {
            if let user = userManager.currentUser {
                preferences = user.notificationPreferences
            }
        }
        .onChange(of: preferences) { _, _ in
            userManager.updateNotificationPreferences(preferences)
            notificationService.updateNotificationPreferences(preferences)
        }
    }
}

struct AppleStyleToggleRow: View {
    let title: String
    let subtitle: String
    let icon: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.blue)
                .frame(width: 24, height: 24)
            
            // Text
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .medium, design: .default))
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.system(size: 14, weight: .regular, design: .default))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Toggle
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct AppleStyleOfflineSettingsSection: View {
    @ObservedObject private var offlineManager = OfflineManager.shared
    @State private var isOfflineModeEnabled = false
    @State private var autoDownloadEnabled = false
    @State private var maxStorageGB = 2.0
    
    var body: some View {
        VStack(spacing: 0) {
            // Section Header
            HStack {
                Text("Offline tilstand")
                    .font(.system(size: 22, weight: .semibold, design: .default))
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            
            // Settings
            VStack(spacing: 0) {
                AppleStyleToggleRow(
                    title: "Offline mode",
                    subtitle: "Læs artikler uden internetforbindelse",
                    icon: "wifi.slash",
                    isOn: $isOfflineModeEnabled
                )
                
                Divider()
                    .padding(.leading, 44)
                
                AppleStyleToggleRow(
                    title: "Auto-download",
                    subtitle: "Download nye artikler automatisk",
                    icon: "arrow.down.circle",
                    isOn: $autoDownloadEnabled
                )
                
                Divider()
                    .padding(.leading, 44)
                
                // Storage Slider
                HStack(spacing: 12) {
                    Image(systemName: "externaldrive")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.orange)
                        .frame(width: 24, height: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Maksimal lagerplads")
                            .font(.system(size: 16, weight: .medium, design: .default))
                            .foregroundColor(.primary)
                        
                        Text("\(String(format: "%.1f", maxStorageGB)) GB")
                            .font(.system(size: 14, weight: .regular, design: .default))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                Slider(value: $maxStorageGB, in: 0.5...10.0, step: 0.5)
                    .accentColor(.orange)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Apple Style Sign Out Section
struct AppleStyleSignOutSection: View {
    @ObservedObject private var signInService = GoogleSignInService.shared
    @State private var showingSignOutAlert = false
    
    var body: some View {
        VStack(spacing: 0) {
            Button(action: {
                showingSignOutAlert = true
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.red)
                        .frame(width: 24, height: 24)
                    
                    Text("Log ud")
                        .font(.system(size: 16, weight: .medium, design: .default))
                        .foregroundColor(.red)
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 20)
            .alert("Log ud", isPresented: $showingSignOutAlert) {
                Button("Annuller", role: .cancel) { }
                Button("Log ud", role: .destructive) {
                    signInService.signOut()
                }
            } message: {
                Text("Er du sikker på, at du vil logge ud?")
            }
        }
        .padding(.bottom, 24)
    }
}

// MARK: - Apple Style Sign In Section
struct AppleStyleSignInSection: View {
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 20) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color(.systemGray5))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(.secondary)
                }
                
                // Text
                VStack(spacing: 8) {
                    Text("Log ind for at fortsætte")
                        .font(.system(size: 24, weight: .semibold, design: .default))
                        .foregroundColor(.primary)
                    
                    Text("Få adgang til din personlige oplevelse, læsestatistik og indstillinger")
                        .font(.system(size: 16, weight: .regular, design: .default))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
                
                // Sign In Button
                GoogleSignInButton()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 32)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 24)
    }
}

// MARK: - Debug Section
struct AppleStyleDebugSection: View {
    @ObservedObject private var notificationService = NotificationService.shared
    @ObservedObject private var userManager = UserManager.shared
    
    var body: some View {
        VStack(spacing: 20) {
            // Debug Header
            HStack {
                Text("Debug Notifikationer")
                    .font(.system(size: 22, weight: .semibold, design: .default))
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            
            // Debug Buttons
            VStack(spacing: 0) {
                Button(action: {
                    NotificationService.shared.sendTestLocalNotification()
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "bell")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.blue)
                            .frame(width: 24, height: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Test Lokal Notifikation")
                                .font(.system(size: 16, weight: .medium, design: .default))
                                .foregroundColor(.primary)
                            
                            Text("Send en lokal test notifikation")
                                .font(.system(size: 14, weight: .regular, design: .default))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(.tertiaryLabel))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(PlainButtonStyle())
                
                Divider()
                    .padding(.leading, 44)
                
                Button(action: {
                    NotificationService.shared.debugNotificationSystem()
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "ladybug")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.orange)
                            .frame(width: 24, height: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Debug System Status")
                                .font(.system(size: 16, weight: .medium, design: .default))
                                .foregroundColor(.primary)
                            
                            Text("Vis detaljeret system status i console")
                                .font(.system(size: 14, weight: .regular, design: .default))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(.tertiaryLabel))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(PlainButtonStyle())
                
                Divider()
                    .padding(.leading, 44)
                
                Button(action: {
                    NotificationService.shared.forceSubscribeToNewArticles()
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.green)
                            .frame(width: 24, height: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Force Abonner på new_articles")
                                .font(.system(size: 16, weight: .medium, design: .default))
                                .foregroundColor(.primary)
                            
                            Text("Abonner direkte på Webflow topic")
                                .font(.system(size: 14, weight: .regular, design: .default))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(.tertiaryLabel))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(PlainButtonStyle())
                
                Divider()
                    .padding(.leading, 44)
                
                Button(action: {
                    if let user = userManager.currentUser {
                        NotificationService.shared.subscribeToTopics(for: user)
                    }
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.2")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.purple)
                            .frame(width: 24, height: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Abonner på Alle Topics")
                                .font(.system(size: 16, weight: .medium, design: .default))
                                .foregroundColor(.primary)
                            
                            Text("Abonner på alle bruger topics")
                                .font(.system(size: 14, weight: .regular, design: .default))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(.tertiaryLabel))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 20)
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView()
            .preferredColorScheme(.dark)
    }
} 
