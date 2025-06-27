//
//  PaywallThirteenSocialProofView.swift
//  Native
//

import SwiftUI

struct PaywallThirteenSocialProofView: View {
    
    // MARK: - Properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .contentBackground(isBackgroundColorGradient: true)
    }
}

// MARK: - Item:

private extension PaywallThirteenSocialProofView {
    private var item: some View {
        LazyVGrid(
            columns: columns,
            alignment: .leading,
            spacing: 24
        ) {
            socialProofItemsContent
        }
    }
}

// MARK: - Social proof items:

private extension PaywallThirteenSocialProofView {
    private var socialProofItemsContent: some View {
        ForEach(
            socialProofItems,
            content: socialProofItem
        )
    }
    
    private func socialProofItem(_ item: NT_SocialProof) -> some View {
        HStack(
            alignment: .center,
            spacing: 4
        ) {
            socialProofItemContent(item)
        }
    }
    
    @ViewBuilder
    private func socialProofItemContent(_ item: NT_SocialProof) -> some View {
        socialProofItemIcon(Icons.laurelLeading)
        socialProofItemTitle(item)
        socialProofItemIcon(Icons.laurelTrailing)
    }
    
    private func socialProofItemIcon(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(iconFont)
            .foregroundStyle(color)
            .frame(
                width: iconFrame,
                height: iconFrame,
                alignment: .center
            )
    }
    
    private func socialProofItemTitle(_ item: NT_SocialProof) -> some View {
        Text(title(item))
            .font(titleFont)
            .textCase(.uppercase)
            .multilineTextAlignment(.center)
            .foregroundStyle(color)
            .frame(
                maxWidth: .infinity,
                alignment: .center
            )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        PaywallThirteenSocialProofView()
    }
    .safeAreaPadding(
        .all,
        16
    )
    .safeAreaPadding(
        .bottom,
        16
    )
}
