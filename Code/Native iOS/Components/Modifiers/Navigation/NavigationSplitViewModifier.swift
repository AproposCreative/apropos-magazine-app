//
//  NavigationSplitViewModifier.swift
//  Native
//

import SwiftUI

struct NavigationSplitViewModifier<DetailContent: View>: ViewModifier {
    
    // MARK: - Private properties:
    
    /// 'Bool' value indicating whether or not the view should be embedded into the 'Navigation Split View':
    private let isEmbedding: Bool
    
    /// Width that the sidebar should have if applicable:
    private let sidebarWidth: CGFloat?
    
    /// Content to display as the detail of the 'Navigation Split View':
    private let detailContent: DetailContent
    
    init(
        isEmbedding: Bool,
        sidebarWidth: CGFloat?,
        @ViewBuilder
        detailContent: @escaping () -> DetailContent
    ) {
        
        /// Properties initialization:
        self.isEmbedding = isEmbedding
        self.sidebarWidth = sidebarWidth
        self.detailContent = detailContent()
    }
    
    // MARK: - View:
    
    func body(content: Content) -> some View {
        navigationSplitView(content)
    }
    
    @ViewBuilder
    private func navigationSplitView(_ content: Content) -> some View {
        if isEmbedding {
            navigationSplitViewContent(content)
        } else {
            content
        }
    }
    
    private func navigationSplitViewContent(_ content: Content) -> some View {
        NavigationSplitView {
            sidebar(content)
        } detail: {
            detailContent
        }
    }
}

// MARK: - Sidebar:

private extension NavigationSplitViewModifier {
    @ViewBuilder
    private func sidebar(_ content: Content) -> some View {
        if let sidebarWidth {
            sidebarContent(
                content,
                withWidth: sidebarWidth
            )
        } else {
            content
        }
    }
    
    private func sidebarContent(
        _ content: Content,
        withWidth width: CGFloat
    ) -> some View {
        content
            .navigationSplitViewColumnWidth(width)
    }
}

// MARK: - Modifier:

extension View {
    
    // MARK: - Functions:
    
    /// Returns the modifier that embeds the view into the 'Navigation Split View' if needed:
    func navigationSplitView<DetailContent: View>(
        isEmbedding: Bool = true,
        sidebarWidth: CGFloat? = 400,
        @ViewBuilder
        detailContent: @escaping () -> DetailContent
    ) -> some View {
        modifier(
            NavigationSplitViewModifier(
                isEmbedding: isEmbedding,
                sidebarWidth: sidebarWidth,
                detailContent: detailContent
            )
        )
    }
}

// MARK: - Preview:

#Preview {
    Text("Preview")
        .font(.body)
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
        .padding()
        .navigationTitle("Preview")
        .navigationSplitView(
            isEmbedding: true,
            sidebarWidth: 384
        ) {
            PlaceholderView(title: "Content")
        }
}
