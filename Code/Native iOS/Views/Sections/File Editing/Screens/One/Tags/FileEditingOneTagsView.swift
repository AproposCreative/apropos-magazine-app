//
//  FileEditingOneTagsView.swift
//  Native
//

import SwiftUI

struct FileEditingOneTagsView: View {
    
    // MARK: - Properties:
    
    /// An array of the tags to display:
    let tags: [NT_DesignToolTag]
    
    init(tags: [NT_DesignToolTag]) {
        
        /// Properties initialization:
        self.tags = tags
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    @ViewBuilder
    private var content: some View {
        if isShowing {
            mainContent
        }
    }
    
    @ViewBuilder
    private var mainContent: some View {
        item
            .headerProminence(.increased)
    }
}

// MARK: - Item:

private extension FileEditingOneTagsView {
    private var item: some View {
        Section("Tags") {
            tagsContent
        }
    }
}

// MARK: - Tags:

private extension FileEditingOneTagsView {
    private var tagsContent: some View {
        ForEach(
            tags,
            content: tag
        )
    }
    
    private func tag(_ tag: NT_DesignToolTag) -> some View {
        NavigationLink(value: tag) {
            tagLabel(tag)
        }
    }
    
    private func tagLabel(_ tag: NT_DesignToolTag) -> some View {
        LabelView(
            icon: icon(tag),
            title: title(tag),
            isShowingBadge: true,
            badge: filesCount(tag),
            isBadgeLocalized: false
        )
    }
}

// MARK: - Preview:

#Preview {
    List {
        FileEditingOneTagsView(tags: NT_DesignToolTag.example)
    }
    .listStyle(.insetGrouped)
    .localizedNavigationTitle(
        title: "AppLayouts",
        isLocalized: false
    )
    .navigationDestination(for: NT_DesignToolTag.self) { tag in
        PlaceholderView(title: tag.title)
    }
    .navigationStack()
}
