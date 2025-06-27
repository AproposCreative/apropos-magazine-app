//
//  LocalizedBadgeModifier.swift
//  Native
//

import SwiftUI

struct LocalizedListBadgeModifier: ViewModifier {
    
    // MARK: - Private properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    /// 'Bool' value indicating whether or not the badge should be shown at all:
    private let isShowing: Bool
    
    /// An actual badge to display:
    private let badge: String
    
    /// 'Bool' value indicating whether or not the badge should be localized:
    private let isLocalized: Bool
    
    init(
        isShowing: Bool,
        badge: String,
        isLocalized: Bool
    ) {
        
        /// Properties initialization:
        self.isShowing = isShowing
        self.badge = badge
        self.isLocalized = isLocalized
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the badge should be shown at all:
    private var isShowingBadge: Bool {
        isShowing && !badge.isEmpty
    }
    
    /// 'Bool' value indicating whether or not the content of the view should be moved that is based on the size of the dynamic type that is currently selected:
    private var shouldMoveContent: Bool {
        dynamicTypeSize >= .accessibility1
    }
    
    /// Badge that should be localized:
    private var localizedBadge: LocalizedStringKey {
        .init(badge)
    }
    
    // MARK: - View:
    
    func body(content: Content) -> some View {
        if isShowingBadge {
            self.content(content)
        } else {
            content
        }
    }
    
    @ViewBuilder
    private func content(_ content: Content) -> some View {
        if shouldMoveContent {
            item(content)
        } else {
            badgeContent(content)
        }
    }
}

// MARK: - Item:

private extension LocalizedListBadgeModifier {
    private func item(_ content: Content) -> some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            itemContent(content)
        }
    }
    
    @ViewBuilder
    private func itemContent(_ content: Content) -> some View {
        content
        title
    }
}

// MARK: - Badge:

private extension LocalizedListBadgeModifier {
    @ViewBuilder
    private func badgeContent(_ content: Content) -> some View {
        if isLocalized {
            localizedBadge(content)
        } else {
            nonLocalizedBadge(content)
        }
    }
    
    private func localizedBadge(_ content: Content) -> some View {
        content
            .badge(localizedBadge)
    }
    
    private func nonLocalizedBadge(_ content: Content) -> some View {
        content
            .badge(badge)
    }
}

// MARK: - Title:

private extension LocalizedListBadgeModifier {
    private var title: some View {
        titleContent
            .font(.body)
            .multilineTextAlignment(.leading)
            .foregroundStyle(.secondary)
            .dynamicTextHeight()
    }
    
    @ViewBuilder
    private var titleContent: some View {
        if isLocalized {
            Text(localizedBadge)
        } else {
            Text(badge)
        }
    }
}

// MARK: - Modifier:

extension View {
    
    // MARK: - Functions:
    
    /// Returns the modifier that adds the localized badge to the view in the list if needed:
    func localizedListBadge(
        isShowing: Bool = true,
        badge: String,
        isLocalized: Bool = true
    ) -> some View {
        modifier(
            LocalizedListBadgeModifier(
                isShowing: isShowing,
                badge: badge,
                isLocalized: isLocalized
            )
        )
    }
}

// MARK: - Preview:

#Preview {
    List {
        Label(
            "Title",
            systemImage: Icons.mailStack
        )
        .symbolVariant(.fill)
        .localizedListBadge(
            isShowing: true,
            badge: "Badge",
            isLocalized: true
        )
    }
}
