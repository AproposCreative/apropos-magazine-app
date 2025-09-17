import SwiftUI

// MARK: - iOS 26 Style Top Bar Component

struct iOS26TopBar: View {
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
            // Clean background with subtle blur
            Rectangle()
                .fill(.regularMaterial)
                .frame(height: 100) // Reduced height for cleaner look
                .ignoresSafeArea(edges: .top)
            
            VStack(spacing: 0) {
                // Safe area spacer
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 44)
                
                // Content area with iOS 26 styling
                HStack(spacing: 16) {
                    // Left side - Menu button (minimalist)
                    if showMenuButton {
                        Button(action: onMenu) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        Spacer()
                            .frame(width: 32)
                    }
                    
                    // Center - Title (iOS 26 style)
                    Text(title)
                        .font(.system(size: 17, weight: .semibold, design: .default))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                    
                    // Right side - Action buttons (minimalist)
                    HStack(spacing: 12) {
                        if showSearchButton {
                            Button(action: onSearch) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.primary)
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        if showNotificationButton {
                            Button(action: onNotification) {
                                ZStack {
                                    Image(systemName: "bell")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.primary)
                                    
                                    // Notification badge
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 8, height: 8)
                                        .offset(x: 8, y: -8)
                                }
                                .frame(width: 32, height: 32)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        if showUserMenuButton {
                            Button(action: onUserMenu) {
                                Image(systemName: "person.circle")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.primary)
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .padding(.horizontal, 20)
                .frame(height: 56)
            }
        }
        .sheet(isPresented: $showUserMenu) {
            iOS26UserMenuSheet()
        }
        .sheet(isPresented: $showNotifications) {
            iOS26NotificationsSheet()
        }
    }
}

// MARK: - iOS 26 Style Scrollable Top Bar

struct iOS26ScrollableTopBar: View {
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
            // Clean background with subtle blur
            Rectangle()
                .fill(.regularMaterial)
                .frame(height: showNavTitle ? 100 : 60)
                .ignoresSafeArea(edges: .top)
                .animation(.easeInOut(duration: 0.3), value: showNavTitle)
            
            VStack(spacing: 0) {
                // Safe area spacer
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 44)
                
                // Content area with iOS 26 styling
                HStack(spacing: 16) {
                    // Left side - Menu button (minimalist)
                    if showMenuButton {
                        Button(action: onMenu) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        Spacer()
                            .frame(width: 32)
                    }
                    
                    // Center - Title (iOS 26 style, animated)
                    if showNavTitle {
                        Text(title)
                            .font(.system(size: 17, weight: .semibold, design: .default))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    } else {
                        Spacer()
                    }
                    
                    // Right side - Action buttons (minimalist)
                    HStack(spacing: 12) {
                        if showSearchButton {
                            Button(action: onSearch) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.primary)
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        if showNotificationButton {
                            Button(action: onNotification) {
                                ZStack {
                                    Image(systemName: "bell")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.primary)
                                    
                                    // Notification badge
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 8, height: 8)
                                        .offset(x: 8, y: -8)
                                }
                                .frame(width: 32, height: 32)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        if showUserMenuButton {
                            Button(action: onUserMenu) {
                                Image(systemName: "person.circle")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.primary)
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .padding(.horizontal, 20)
                .frame(height: showNavTitle ? 56 : 16)
                .animation(.easeInOut(duration: 0.3), value: showNavTitle)
            }
        }
        .sheet(isPresented: $showUserMenu) {
            iOS26UserMenuSheet()
        }
        .sheet(isPresented: $showNotifications) {
            iOS26NotificationsSheet()
        }
    }
}

// MARK: - iOS 26 Style User Menu Sheet

struct iOS26UserMenuSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Menu")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.blue)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                
                Divider()
                
                // Menu items
                VStack(spacing: 0) {
                    iOS26MenuRow(icon: "person.circle", title: "Profile", action: {})
                    iOS26MenuRow(icon: "gear", title: "Settings", action: {})
                    iOS26MenuRow(icon: "questionmark.circle", title: "Help", action: {})
                    iOS26MenuRow(icon: "info.circle", title: "About", action: {})
                }
                
                Spacer()
            }
            .background(Color(.systemGroupedBackground))
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - iOS 26 Style Notifications Sheet

struct iOS26NotificationsSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Notifications")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.blue)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                
                Divider()
                
                // Notifications content
                VStack(spacing: 16) {
                    Text("No new notifications")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .padding(.top, 40)
                    
                    Spacer()
                }
            }
            .background(Color(.systemGroupedBackground))
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - iOS 26 Style Menu Row Component

struct iOS26MenuRow: View {
    let icon: String
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 24, height: 24)
                
                Text(title)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(.systemBackground))
        }
        .buttonStyle(PlainButtonStyle())
        
        Divider()
            .padding(.leading, 60)
    }
}

// MARK: - View Extensions for iOS 26 Style

extension View {
    func ios26TopBar(
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
            
            iOS26TopBar(
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
    
    func ios26ScrollableTopBar(
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
            
            iOS26ScrollableTopBar(
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

// MARK: - Preview

#Preview {
    VStack {
        Text("Content")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
    }
    .ios26TopBar(
        title: "iOS 26 Style",
        showSearchButton: true,
        showMenuButton: true,
        showNotificationButton: true,
        showUserMenuButton: true,
        onSearch: { print("Search tapped") },
        onMenu: { print("Menu tapped") },
        onNotification: { print("Notification tapped") },
        onUserMenu: { print("User menu tapped") }
    )
}
