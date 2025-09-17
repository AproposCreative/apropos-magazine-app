import SwiftUI

struct EmptyStateView: View {
    
    // MARK: - Properties
    
    private let icon: String
    private let title: String
    private let subtitle: String
    private let actionTitle: String?
    private let action: (() -> Void)?
    
    init(
        icon: String = "doc.text.magnifyingglass",
        title: String = "Ingen artikler fundet",
        subtitle: String = "Prøv at søge efter noget andet eller tjek din internetforbindelse.",
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.action = action
    }
    
    // MARK: - View
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Icon
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary)
                .padding(.bottom, 8)
            
            // Title
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
            
            // Subtitle
            Text(subtitle)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            // Action Button (optional)
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.top, 8)
            }
            
            Spacer()
        }
        .padding()
    }
}

// MARK: - Preview

#Preview {
    EmptyStateView(
        icon: "doc.text.magnifyingglass",
        title: "Ingen artikler fundet",
        subtitle: "Prøv at søge efter noget andet eller tjek din internetforbindelse.",
        actionTitle: "Prøv igen"
    ) {
        print("Action tapped")
    }
} 