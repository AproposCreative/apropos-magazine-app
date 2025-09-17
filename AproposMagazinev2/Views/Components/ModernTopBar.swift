import SwiftUI

// MARK: - Modern Top Bar Component

struct ModernTopBar: View {
    let title: String
    let showSearchButton: Bool
    let showMenuButton: Bool
    let showNotificationButton: Bool
    let showUserMenuButton: Bool
    let onSearch: () -> Void
    let onMenu: () -> Void
    let onNotification: () -> Void
    let onUserMenu: () -> Void
    @Environment(\.colorScheme) var colorScheme
    @State private var showUserMenu = false
    @State private var showNotifications = false
    
    var body: some View {
        ZStack(alignment: .top) {
            // Background with glass effect
            Rectangle()
                .fill(.ultraThinMaterial)
                .frame(height: 104) // 44 (safe area) + 60 (content)
                .ignoresSafeArea(edges: .top)
            
            VStack(spacing: 0) {
                // Safe area spacer
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 44)
                
                // Content area
                HStack {
                    // Left side - Menu button
                    if showMenuButton {
                        Button(action: onMenu) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.primary)
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle()
                                        .fill(Color.secondary.opacity(0.1))
                                )
                        }
                        .buttonStyle(ModernButtonStyle())
                    } else {
                        Spacer()
                            .frame(width: 44)
                    }
                    
                    Spacer()
                    
                    // Center - Title
                    Text(title)
                        .font(.system(size: 20, weight: .semibold, design: .default))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Right side - Action buttons
                    HStack(spacing: 8) {
                        // Search button
                        if showSearchButton {
                            Button(action: onSearch) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.primary)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        Circle()
                                            .fill(Color.secondary.opacity(0.1))
                                    )
                            }
                            .buttonStyle(ModernButtonStyle())
                        }
                        
                        // Notification button
                        if showNotificationButton {
                            Button(action: { showNotifications = true }) {
                                ZStack {
                                    Image(systemName: "bell")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundColor(.primary)
                                        .frame(width: 44, height: 44)
                                        .background(
                                            Circle()
                                                .fill(Color.secondary.opacity(0.1))
                                        )
                                    
                                    // Notification badge
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 8, height: 8)
                                        .offset(x: 12, y: -12)
                                }
                            }
                            .buttonStyle(ModernButtonStyle())
                        }
                        
                        // User menu button
                        if showUserMenuButton {
                            Button(action: { showUserMenu = true }) {
                                Image(systemName: "person.circle")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.primary)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        Circle()
                                            .fill(Color.secondary.opacity(0.1))
                                    )
                            }
                            .buttonStyle(ModernButtonStyle())
                        }
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 60)
            }
        }
        .zIndex(1)
        .ignoresSafeArea(edges: .top)
        .sheet(isPresented: $showUserMenu) {
            UserMenuSheet()
        }
        .sheet(isPresented: $showNotifications) {
            NotificationsSheet()
        }
    }
}

// MARK: - Modern Button Style

struct ModernButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Scrollable Top Bar (for views with scroll)

struct ScrollableModernTopBar: View {
    let title: String
    let showSearchButton: Bool
    let showMenuButton: Bool
    let showNotificationButton: Bool
    let showUserMenuButton: Bool
    let onSearch: () -> Void
    let onMenu: () -> Void
    let onNotification: () -> Void
    let onUserMenu: () -> Void
    @Binding var showNavTitle: Bool
    @Environment(\.colorScheme) var colorScheme
    @State private var showUserMenu = false
    @State private var showNotifications = false
    
    var body: some View {
        ZStack(alignment: .top) {
            // Background with glass effect
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(showNavTitle ? 1.0 : 0.0)
                .frame(height: 104) // 44 (safe area) + 60 (content)
                .ignoresSafeArea(edges: .top)
                .animation(.easeInOut(duration: 0.2), value: showNavTitle)
            
            VStack(spacing: 0) {
                // Safe area spacer
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 44)
                
                // Content area
                HStack {
                    // Left side - Menu button
                    if showMenuButton {
                        Button(action: onMenu) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.primary)
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle()
                                        .fill(Color.secondary.opacity(0.1))
                                )
                        }
                        .buttonStyle(ModernButtonStyle())
                    } else {
                        Spacer()
                            .frame(width: 44)
                    }
                    
                    Spacer()
                    
                    // Center - Title
                    Text(title)
                        .font(.system(size: 20, weight: .semibold, design: .default))
                        .foregroundColor(.primary)
                        .opacity(showNavTitle ? 1.0 : 0.0)
                        .animation(.easeInOut(duration: 0.2), value: showNavTitle)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Right side - Action buttons
                    HStack(spacing: 8) {
                        // Search button
                        if showSearchButton {
                            Button(action: onSearch) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.primary)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        Circle()
                                            .fill(Color.secondary.opacity(0.1))
                                    )
                            }
                            .buttonStyle(ModernButtonStyle())
                        }
                        
                        // Notification button
                        if showNotificationButton {
                            Button(action: { showNotifications = true }) {
                                ZStack {
                                    Image(systemName: "bell")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundColor(.primary)
                                        .frame(width: 44, height: 44)
                                        .background(
                                            Circle()
                                                .fill(Color.secondary.opacity(0.1))
                                        )
                                    
                                    // Notification badge
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 8, height: 8)
                                        .offset(x: 12, y: -12)
                                }
                            }
                            .buttonStyle(ModernButtonStyle())
                        }
                        
                        // User menu button
                        if showUserMenuButton {
                            Button(action: { showUserMenu = true }) {
                                Image(systemName: "person.circle")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.primary)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        Circle()
                                            .fill(Color.secondary.opacity(0.1))
                                    )
                            }
                            .buttonStyle(ModernButtonStyle())
                        }
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 60)
            }
        }
        .zIndex(1)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
        .sheet(isPresented: $showUserMenu) {
            UserMenuSheet()
        }
        .sheet(isPresented: $showNotifications) {
            NotificationsSheet()
        }
    }
}

// MARK: - View Extension for Easy Integration

extension View {
    func modernTopBar(
        title: String,
        showSearchButton: Bool = true,
        showMenuButton: Bool = true,
        showNotificationButton: Bool = false,
        showUserMenuButton: Bool = false,
        onSearch: @escaping () -> Void = {},
        onMenu: @escaping () -> Void = {},
        onNotification: @escaping () -> Void = {},
        onUserMenu: @escaping () -> Void = {}
    ) -> some View {
        ZStack(alignment: .top) {
            self
            
            ModernTopBar(
                title: title,
                showSearchButton: showSearchButton,
                showMenuButton: showMenuButton,
                showNotificationButton: showNotificationButton,
                showUserMenuButton: showUserMenuButton,
                onSearch: onSearch,
                onMenu: onMenu,
                onNotification: onNotification,
                onUserMenu: onUserMenu
            )
        }
    }
    
    func scrollableModernTopBar(
        title: String,
        showNavTitle: Binding<Bool>,
        showSearchButton: Bool = true,
        showMenuButton: Bool = true,
        showNotificationButton: Bool = false,
        showUserMenuButton: Bool = false,
        onSearch: @escaping () -> Void = {},
        onMenu: @escaping () -> Void = {},
        onNotification: @escaping () -> Void = {},
        onUserMenu: @escaping () -> Void = {}
    ) -> some View {
        ZStack(alignment: .top) {
            self
            
            ScrollableModernTopBar(
                title: title,
                showSearchButton: showSearchButton,
                showMenuButton: showMenuButton,
                showNotificationButton: showNotificationButton,
                showUserMenuButton: showUserMenuButton,
                onSearch: onSearch,
                onMenu: onMenu,
                onNotification: onNotification,
                onUserMenu: onUserMenu,
                showNavTitle: showNavTitle
            )
        }
    }
}

// MARK: - User Menu Sheet

struct UserMenuSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // User Profile Section
                VStack(spacing: 12) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("Bruger Profil")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("user@example.com")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)
                
                // Menu Items
                VStack(spacing: 0) {
                    MenuRow(icon: "person", title: "Min Profil", action: {})
                    MenuRow(icon: "heart", title: "Mine Favoritter", action: {})
                    MenuRow(icon: "bell", title: "Notifikationer", action: {})
                    MenuRow(icon: "gear", title: "Indstillinger", action: {})
                    MenuRow(icon: "questionmark.circle", title: "Hjælp & Support", action: {})
                    MenuRow(icon: "info.circle", title: "Om Appen", action: {})
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                )
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Sign Out Button
                Button(action: {}) {
                    Text("Log Ud")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.red)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle("Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Luk") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Notifications Sheet

struct NotificationsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Empty State
                VStack(spacing: 16) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    
                    Text("Ingen Notifikationer")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Du har ingen nye notifikationer lige nu.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 60)
                
                Spacer()
            }
            .navigationTitle("Notifikationer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Luk") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Menu Row Component

struct MenuRow: View {
    let icon: String
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(.blue)
                    .frame(width: 24)
                
                Text(title)
                    .font(.body)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // Static top bar
        ModernTopBar(
            title: "Kategorier",
            showSearchButton: true,
            showMenuButton: true,
            showNotificationButton: true,
            showUserMenuButton: true,
            onSearch: { print("Search tapped") },
            onMenu: { print("Menu tapped") },
            onNotification: { print("Notification tapped") },
            onUserMenu: { print("User menu tapped") }
        )
        
        // Scrollable top bar
        ScrollableModernTopBar(
            title: "Alle Artikler",
            showSearchButton: true,
            showMenuButton: true,
            showNotificationButton: true,
            showUserMenuButton: true,
            onSearch: { print("Search tapped") },
            onMenu: { print("Menu tapped") },
            onNotification: { print("Notification tapped") },
            onUserMenu: { print("User menu tapped") },
            showNavTitle: .constant(true)
        )
        
        Spacer()
    }
    .background(Color(.systemGroupedBackground))
}

// MARK: - View Extensions

extension View {
    func modernTopBar(
        title: String,
        showSearchButton: Bool = true,
        showMenuButton: Bool = true,
        showNotificationButton: Bool = false,
        showUserMenuButton: Bool = false,
        onSearch: @escaping () -> Void = {},
        onMenu: @escaping () -> Void = {},
        onNotification: @escaping () -> Void = {},
        onUserMenu: @escaping () -> Void = {}
    ) -> some View {
        self.overlay(
            ModernTopBar(
                title: title,
                showSearchButton: showSearchButton,
                showMenuButton: showMenuButton,
                showNotificationButton: showNotificationButton,
                showUserMenuButton: showUserMenuButton,
                onSearch: onSearch,
                onMenu: onMenu,
                onNotification: onNotification,
                onUserMenu: onUserMenu
            ),
            alignment: .top
        )
    }
    
    func scrollableModernTopBar(
        title: String,
        showNavTitle: Binding<Bool>,
        showSearchButton: Bool = true,
        showMenuButton: Bool = true,
        showNotificationButton: Bool = false,
        showUserMenuButton: Bool = false,
        onSearch: @escaping () -> Void = {},
        onMenu: @escaping () -> Void = {},
        onNotification: @escaping () -> Void = {},
        onUserMenu: @escaping () -> Void = {}
    ) -> some View {
        self.overlay(
            ScrollableModernTopBar(
                title: title,
                showSearchButton: showSearchButton,
                showMenuButton: showMenuButton,
                showNotificationButton: showNotificationButton,
                showUserMenuButton: showUserMenuButton,
                onSearch: onSearch,
                onMenu: onMenu,
                onNotification: onNotification,
                onUserMenu: onUserMenu,
                showNavTitle: showNavTitle
            ),
            alignment: .top
        )
    }
}
