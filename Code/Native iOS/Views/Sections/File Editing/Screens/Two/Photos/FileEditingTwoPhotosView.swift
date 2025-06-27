//
//  FileEditingTwoPhotosView.swift
//  Native
//

import SwiftUI

struct FileEditingTwoPhotosView: View {
    
    // MARK: - Properties:
    
    /// An actual category to display the photos for:
    let category: NT_PhotoEditorCategory
    
    // MARK: - Private properties:
    
    /// Photo that is currently selected:
    @State private var selectedPhoto: NT_PhotoEditorPhoto? = nil
    
    init(category: NT_PhotoEditorCategory) {
        
        /// Properties initialization:
        self.category = category
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        scroll
            .background(Color(.systemGroupedBackground))
            .localizedNavigationTitle(
                title: title,
                isLocalized: false
            )
            .toolbarButton(
                title: "New Photo",
                icon: Icons.plusCircle,
                font: .body,
                style: .iconOnly,
                action: newPhoto
            )
            .sheet(
                item: $selectedPhoto,
                content: FileEditingTwoDetailsView.init
            )
    }
}

// MARK: - Scroll:

private extension FileEditingTwoPhotosView {
    private var scroll: some View {
        scrollContent
            .safeAreaPadding(
                .all,
                16
            )
            .safeAreaPadding(
                .bottom,
                16
            )
    }
    
    private var scrollContent: some View {
        ScrollView {
            scrollItem
        }
    }
    
    @ViewBuilder
    private var scrollItem: some View {
        if isEmpty {
            noPhotos
        } else {
            sectionsContent
        }
    }
}

// MARK: - No photos:

private extension FileEditingTwoPhotosView {
    private var noPhotos: some View {
        noPhotosContent
            .frame(
                maxWidth: .infinity,
                alignment: .center
            )
            .containerRelativeFrame(
                .vertical,
                alignment: .center
            )
    }
    
    private var noPhotosContent: some View {
        EmptyStateView(
            title: "No Photos",
            subtitle: "Just add a photo and it will appear here."
        )
    }
}

// MARK: - Sections:

private extension FileEditingTwoPhotosView {
    private var sectionsContent: some View {
        LazyVStack(
            alignment: .leading,
            spacing: 32
        ) {
            sectionsItem
        }
    }
    
    private var sectionsItem: some View {
        ForEach(
            sections,
            content: section
        )
    }
    
    private func section(_ section: NT_PhotoEditorSection) -> some View {
        FileEditingTwoSectionView(
            section: section,
            selectedPhoto: $selectedPhoto
        )
    }
}

// MARK: - Preview:

#Preview {
    FileEditingTwoPhotosView(category: .example.first { $0.id == "Item.3" }!)
        .navigationStack()
}
