import SwiftUI

// MARK: - Modern Top Bar Component

struct ModernTopBar: View {
    let title: String
    let showSearchButton: Bool
    let showMenuButton: Bool
    let onSearch: () -> Void
    let onMenu: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
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
                    
                    // Right side - Search button
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
                    } else {
                        Spacer()
                            .frame(width: 44)
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 60)
            }
        }
        .zIndex(1)
        .ignoresSafeArea(edges: .top)
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
    let onSearch: () -> Void
    let onMenu: () -> Void
    @Binding var showNavTitle: Bool
    @Environment(\.colorScheme) var colorScheme
    
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
                    
                    // Right side - Search button
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
                    } else {
                        Spacer()
                            .frame(width: 44)
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 60)
            }
        }
        .zIndex(1)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }
}

// MARK: - View Extension for Easy Integration

extension View {
    func modernTopBar(
        title: String,
        showSearchButton: Bool = true,
        showMenuButton: Bool = true,
        onSearch: @escaping () -> Void = {},
        onMenu: @escaping () -> Void = {}
    ) -> some View {
        ZStack(alignment: .top) {
            self
            
            ModernTopBar(
                title: title,
                showSearchButton: showSearchButton,
                showMenuButton: showMenuButton,
                onSearch: onSearch,
                onMenu: onMenu
            )
        }
    }
    
    func scrollableModernTopBar(
        title: String,
        showNavTitle: Binding<Bool>,
        showSearchButton: Bool = true,
        showMenuButton: Bool = true,
        onSearch: @escaping () -> Void = {},
        onMenu: @escaping () -> Void = {}
    ) -> some View {
        ZStack(alignment: .top) {
            self
            
            ScrollableModernTopBar(
                title: title,
                showSearchButton: showSearchButton,
                showMenuButton: showMenuButton,
                onSearch: onSearch,
                onMenu: onMenu,
                showNavTitle: showNavTitle
            )
        }
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
            onSearch: { print("Search tapped") },
            onMenu: { print("Menu tapped") }
        )
        
        // Scrollable top bar
        ScrollableModernTopBar(
            title: "Alle Artikler",
            showSearchButton: true,
            showMenuButton: true,
            onSearch: { print("Search tapped") },
            onMenu: { print("Menu tapped") },
            showNavTitle: .constant(true)
        )
        
        Spacer()
    }
    .background(Color(.systemGroupedBackground))
}
