import SwiftUI

struct AppHeader: View {
    let title: String?
    let showBackButton: Bool
    let showLogo: Bool
    let showSearch: Bool
    let showMenu: Bool
    let onBack: (() -> Void)?
    let onSearch: (() -> Void)?
    let onMenu: (() -> Void)?
    
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.presentationMode) var presentationMode
    
    init(
        title: String? = nil,
        showBackButton: Bool = false,
        showLogo: Bool = true,
        showSearch: Bool = false,
        showMenu: Bool = false,
        onBack: (() -> Void)? = nil,
        onSearch: (() -> Void)? = nil,
        onMenu: (() -> Void)? = nil
    ) {
        self.title = title
        self.showBackButton = showBackButton
        self.showLogo = showLogo
        self.showSearch = showSearch
        self.showMenu = showMenu
        self.onBack = onBack
        self.onSearch = onSearch
        self.onMenu = onMenu
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Back button
            if showBackButton {
                Button(action: {
                    if let onBack = onBack {
                        onBack()
                    } else {
                        presentationMode.wrappedValue.dismiss()
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                }
            }
            
            // Logo or Title
            if showLogo {
                LogoView()
                    .frame(height: 22)
            } else if let title = title {
                Text(title)
                    .font(.custom("SFProDisplay-Bold", size: 18))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            // Search button
            if showSearch {
                Button(action: {
                    onSearch?()
                }) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.primary)
                }
            }
            
            // Menu button
            if showMenu {
                Button(action: {
                    onMenu?()
                }) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.primary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
}



#Preview {
    VStack(spacing: 20) {
        AppHeader(title: "Hjem")
        AppHeader(title: "Artikel", showBackButton: true)
        AppHeader(showSearch: true, showMenu: true)
    }
    .padding()
}
