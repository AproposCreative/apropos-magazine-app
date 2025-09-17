import SwiftUI

// MARK: - View Extensions

extension View {
    
    // MARK: - Card Styling (din visuelle identitet)
    
    /// Applies Apropos card styling with your visual identity
    func aproposCardStyle() -> some View {
        self
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
    
    /// Applies Apropos button styling
    func aproposButtonStyle() -> some View {
        self
            .font(.headline)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.accentColor)
            .foregroundColor(.white)
            .cornerRadius(10)
    }
    
    /// Applies Apropos secondary button styling
    func aproposSecondaryButtonStyle() -> some View {
        self
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.systemGray5))
            .foregroundColor(.primary)
            .cornerRadius(8)
    }
    
    // MARK: - Spacing (konsistent med din app)
    
    /// Standard horizontal padding for Apropos app
    func aproposHorizontalPadding() -> some View {
        self.padding(.horizontal, 16)
    }
    
    /// Standard section spacing for Apropos app
    func aproposSectionSpacing() -> some View {
        self.padding(.vertical, 24)
    }
    
    // MARK: - Typography (din visuelle identitet)
    
    /// Apropos article title styling
    func aproposArticleTitle() -> some View {
        self
            .font(.title2.weight(.bold))
            .foregroundColor(.primary)
            .multilineTextAlignment(.leading)
    }
    
    /// Apropos article subtitle styling
    func aproposArticleSubtitle() -> some View {
        self
            .font(.subheadline)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.leading)
    }
    
    // MARK: - Loading States
    
    /// Shows loading state with Apropos styling
    func aproposLoadingOverlay(_ isLoading: Bool, title: String? = nil) -> some View {
        self.overlay(
            LoadingView(isShowing: isLoading, title: title)
                .background(Color(.systemBackground).opacity(0.8))
        )
    }
}

// MARK: - Color Extensions (din farvepalette)

extension Color {
    /// Apropos brand colors - bevar din visuelle identitet
    static let aproposPrimary = Color.accentColor
    static let aproposSecondary = Color(.systemGray5)
    static let aproposBackground = Color(.systemBackground)
    static let aproposCardBackground = Color(.systemBackground)
    

} 