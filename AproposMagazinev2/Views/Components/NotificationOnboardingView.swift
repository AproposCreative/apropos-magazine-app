import SwiftUI

struct NotificationOnboardingView: View {
    @ObservedObject private var notificationService = NotificationService.shared
    @EnvironmentObject private var viewModel: ArticleViewModel
    @Environment(\.colorScheme) private var colorScheme
    let onDismiss: () -> Void
    
    @State private var isProcessing = false
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 52))
                .foregroundStyle(.primary, .secondary)
                .accessibilityHidden(true)
                .staggeredReveal(index: 0)
            
            VStack(spacing: 12) {
                Text("Hold dig opdateret")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                
                Text("Få besked, når nye artikler og podcasts udkommer på Apropos Magazine. Du kan altid slå det fra under Indstillinger.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 8)
            .staggeredReveal(index: 1, baseDelay: 0.05)
            
            Spacer()
            
            VStack(spacing: 12) {
                Button {
                    Task {
                        isProcessing = true
                        await notificationService.completeOnboarding(
                            allowNotifications: true,
                            allCategoryIds: viewModel.topics.map(\.id)
                        )
                        isProcessing = false
                        onDismiss()
                    }
                } label: {
                    Text("Tillad notifikationer")
                        .font(.system(.headline, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(colorScheme == .dark ? Color.white : Color.blue)
                        .foregroundColor(colorScheme == .dark ? Color.black : Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isProcessing)
                
                Button("Ikke nu") {
                    Task {
                        isProcessing = true
                        await notificationService.completeOnboarding(
                            allowNotifications: false,
                            allCategoryIds: viewModel.topics.map(\.id)
                        )
                        isProcessing = false
                        onDismiss()
                    }
                }
                .foregroundStyle(.secondary)
                .disabled(isProcessing)
            }
            .staggeredReveal(index: 2, baseDelay: 0.1)
        }
        .padding(24)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled()
    }
}
