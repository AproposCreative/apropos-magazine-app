//
//  PaywallTwelveLegalView.swift
//  Native
//

import SwiftUI

struct PaywallTwelveLegalView: View {
    
    // MARK: - Properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    // MARK: - Private properties:
    
    /// Color of the view:
    private let color: Color
    
    /// Color of the divider:
    private let dividerColor: Color
    
    /// 'Bool' value indicating whether or not the data is currently being fetched:
    private let isFetching: Bool
    
    init(
        color: Color = .secondary,
        dividerColor: Color = .init(.systemFill),
        isFetching: Bool
    ) {
        
        /// Properties initialization:
        self.color = color
        self.dividerColor = dividerColor
        self.isFetching = isFetching
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    @ViewBuilder
    private var content: some View {
        if shouldMoveContent {
            verticalItem
        } else {
            horizontalItem
        }
    }
}

// MARK: - Item:

private extension PaywallTwelveLegalView {
    private var verticalItem: some View {
        VStack(
            alignment: .center,
            spacing: spacing
        ) {
            item
        }
    }
    
    private var horizontalItem: some View {
        HStack(
            alignment: .center,
            spacing: spacing
        ) {
            item
        }
    }
    
    @ViewBuilder
    private var item: some View {
        restoreButton
        divider
        termsOfServiceButton
        divider
        privacyPolicyButton
    }
}

// MARK: - Divider:

private extension PaywallTwelveLegalView {
    @ViewBuilder
    private var divider: some View {
        if shouldMoveContent {
            verticalDivider
        } else {
            horizontalDivider
        }
    }
    
    private var verticalDivider: some View {
        dividerContent
            .frame(
                height: 1,
                alignment: .center
            )
    }
    
    private var horizontalDivider: some View {
        dividerContent
            .frame(
                width: 1,
                height: 12,
                alignment: .center
            )
    }
    
    private var dividerContent: some View {
        RoundedRectangle(
            cornerRadius: 0.5,
            style: .continuous
        )
        .fill(dividerColor)
    }
}

// MARK: - Buttons:

private extension PaywallTwelveLegalView {
    private var restoreButton: some View {
        restoreButtonContent
            .disabled(isFetching)
    }
    
    private var restoreButtonContent: some View {
        Button {
            restore()
        } label: {
            restoreLabel
        }
    }
    
    private var restoreLabel: some View {
        label(
            withTitle: "Restore",
            isLoading: isFetching
        )
    }
    
    private var termsOfServiceButton: some View {
        Link(destination: termsOfServiceLink) {
            label(withTitle: "Terms of Service")
        }
    }
    
    private var privacyPolicyButton: some View {
        Link(destination: privacyPolicyLink) {
            label(withTitle: "Privacy Policy")
        }
    }
    
    @ViewBuilder
    private func label(
        withTitle title: LocalizedStringKey,
        isLoading: Bool = false
    ) -> some View {
        if isLoading {
            LoadingView(isShowing: isLoading)
        } else {
            labelTitle(title)
        }
    }
    
    private func labelTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.caption2)
            .multilineTextAlignment(.center)
            .foregroundStyle(color)
            .frame(
                minHeight: 44,
                alignment: .center
            )
            .frame(
                maxWidth: .infinity,
                alignment: .center
            )
    }
}

// MARK: - Preview:

#Preview {
    PaywallTwelveLegalView(
        color: .secondary,
        dividerColor: .init(.systemFill),
        isFetching: false
    )
    .padding()
}
