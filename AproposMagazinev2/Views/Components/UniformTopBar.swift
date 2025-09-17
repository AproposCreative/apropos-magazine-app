import SwiftUI

// MARK: - Uniform Top Bar Component
// This provides a consistent top bar structure across all views

struct UniformTopBar: View {
    let title: String
    let showBackButton: Bool
    let showSearchButton: Bool
    let showMenuButton: Bool
    let onBack: (() -> Void)?
    let onSearch: (() -> Void)?
    let onMenu: (() -> Void)?
    
    @Environment(\.colorScheme) private var colorScheme
    
    init(
        title: String,
        showBackButton: Bool = false,
        showSearchButton: Bool = false,
        showMenuButton: Bool = false,
        onBack: (() -> Void)? = nil,
        onSearch: (() -> Void)? = nil,
        onMenu: (() -> Void)? = nil
    ) {
        self.title = title
        self.showBackButton = showBackButton
        self.showSearchButton = showSearchButton
        self.showMenuButton = showMenuButton
        self.onBack = onBack
        self.onSearch = onSearch
        self.onMenu = onMenu
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Safe area spacer
            Rectangle()
                .fill(Color.clear)
                .frame(height: 44)
            
            // Main top bar content
            HStack(spacing: 16) {
                // Left side - Back button or spacer
                if showBackButton {
                    Button(action: {
                        onBack?()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(width: 32, height: 32)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(Circle())
                    }
                } else {
                    Spacer()
                        .frame(width: 32)
                }
                
                // Center - Title
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                
                // Right side - Action buttons
                HStack(spacing: 12) {
                    if showSearchButton {
                        Button(action: {
                            onSearch?()
                        }) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                                .frame(width: 32, height: 32)
                                .background(Color.gray.opacity(0.1))
                                .clipShape(Circle())
                        }
                    }
                    
                    if showMenuButton {
                        Button(action: {
                            onMenu?()
                        }) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                                .frame(width: 32, height: 32)
                                .background(Color.gray.opacity(0.1))
                                .clipShape(Circle())
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Divider()
                        .opacity(0.3),
                    alignment: .bottom
                )
        )
        .ignoresSafeArea(edges: .top)
    }
}

// MARK: - View Modifier for Uniform Top Bar
struct UniformTopBarModifier: ViewModifier {
    let title: String
    let showBackButton: Bool
    let showSearchButton: Bool
    let showMenuButton: Bool
    let onBack: (() -> Void)?
    let onSearch: (() -> Void)?
    let onMenu: (() -> Void)?
    
    init(
        title: String,
        showBackButton: Bool = false,
        showSearchButton: Bool = false,
        showMenuButton: Bool = false,
        onBack: (() -> Void)? = nil,
        onSearch: (() -> Void)? = nil,
        onMenu: (() -> Void)? = nil
    ) {
        self.title = title
        self.showBackButton = showBackButton
        self.showSearchButton = showSearchButton
        self.showMenuButton = showMenuButton
        self.onBack = onBack
        self.onSearch = onSearch
        self.onMenu = onMenu
    }
    
    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content
            
            UniformTopBar(
                title: title,
                showBackButton: showBackButton,
                showSearchButton: showSearchButton,
                showMenuButton: showMenuButton,
                onBack: onBack,
                onSearch: onSearch,
                onMenu: onMenu
            )
        }
        .navigationBarHidden(true)
    }
}

// MARK: - View Extension
extension View {
    func uniformTopBar(
        title: String,
        showBackButton: Bool = false,
        showSearchButton: Bool = false,
        showMenuButton: Bool = false,
        onBack: (() -> Void)? = nil,
        onSearch: (() -> Void)? = nil,
        onMenu: (() -> Void)? = nil
    ) -> some View {
        self.modifier(
            UniformTopBarModifier(
                title: title,
                showBackButton: showBackButton,
                showSearchButton: showSearchButton,
                showMenuButton: showMenuButton,
                onBack: onBack,
                onSearch: onSearch,
                onMenu: onMenu
            )
        )
    }
}

// MARK: - Preview
struct UniformTopBar_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            UniformTopBar(
                title: "Profil",
                showSearchButton: true,
                showMenuButton: true
            )
            
            Spacer()
            
            Text("Content goes here")
                .font(.title)
        }
        .background(Color(.systemBackground))
    }
}

