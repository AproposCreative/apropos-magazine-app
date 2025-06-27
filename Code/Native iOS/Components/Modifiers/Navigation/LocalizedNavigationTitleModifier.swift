//
//  LocalizedNavigationTitleModifier.swift
//  Native
//

import SwiftUI

struct LocalizedNavigationTitleModifier: ViewModifier {
    
    // MARK: - Private properties:
    
    /// 'Bool' value indicating whether or not the title should be shown at all:
    private let isShowing: Bool
    
    /// An actual title to display:
    private let title: String
    
    /// 'Bool' value indicating whether or not the title should be localized:
    private let isLocalized: Bool
    
    /// Display mode of the title:
    private let displayMode: NavigationBarItem.TitleDisplayMode
    
    init(
        isShowing: Bool,
        title: String,
        isLocalized: Bool,
        displayMode: NavigationBarItem.TitleDisplayMode
    ) {
        
        /// Properties initialization:
        self.isShowing = isShowing
        self.title = title
        self.isLocalized = isLocalized
        self.displayMode = displayMode
    }
    
    // MARK: - View:
    
    func body(content: Content) -> some View {
        self.content(content)
    }
    
    private func content(_ content: Content) -> some View {
        mainContent(content)
            .navigationBarTitleDisplayMode(displayMode)
    }
    
    @ViewBuilder
    private func mainContent(_ content: Content) -> some View {
        if isShowing {
            item(content)
        } else {
            content
        }
    }
}

// MARK: - Item:

private extension LocalizedNavigationTitleModifier {
    @ViewBuilder
    private func item(_ content: Content) -> some View {
        if isLocalized {
            localizedItem(content)
        } else {
            nonLocalizedItem(content)
        }
    }
    
    private func localizedItem(_ content: Content) -> some View {
        content
            .navigationTitle(.init(title))
    }
    
    private func nonLocalizedItem(_ content: Content) -> some View {
        content
            .navigationTitle(title)
    }
}

// MARK: - Modifier:

extension View {
    
    // MARK: - Functions:
    
    /// Returns the modifier that adds the localized navigation title to the view if needed:
    func localizedNavigationTitle(
        isShowing: Bool = true,
        title: String,
        isLocalized: Bool = true,
        displayMode: NavigationBarItem.TitleDisplayMode = .automatic
    ) -> some View {
        modifier(
            LocalizedNavigationTitleModifier(
                isShowing: isShowing,
                title: title,
                isLocalized: isLocalized,
                displayMode: displayMode
            )
        )
    }
}

// MARK: - Preview:

#Preview {
    List {
        Text("Preview")
    }
    .localizedNavigationTitle(
        isShowing: true,
        title: "Preview",
        isLocalized: true,
        displayMode: .automatic
    )
    .navigationStack()
}
