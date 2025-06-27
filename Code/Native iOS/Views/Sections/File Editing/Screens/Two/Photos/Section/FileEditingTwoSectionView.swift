//
//  FileEditingTwoSectionView.swift
//  Native
//

import SwiftUI

struct FileEditingTwoSectionView: View {
    
    // MARK: - Properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    /// Photo that is currently selected:
    @Binding var selectedPhoto: NT_PhotoEditorPhoto?
    
    /// An actual section to display:
    let section: NT_PhotoEditorSection
    
    init(
        section: NT_PhotoEditorSection,
        selectedPhoto: Binding<NT_PhotoEditorPhoto?>
    ) {
        
        /// Properties initialization:
        self.section = section
        _selectedPhoto = selectedPhoto
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    @ViewBuilder
    private var content: some View {
        if isShowing {
            item
        }
    }
}

// MARK: - Item:

private extension FileEditingTwoSectionView {
    private var item: some View {
        VStack(
            alignment: .leading,
            spacing: spacing
        ) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        header
        photosContent
    }
}

// MARK: - Header:

private extension FileEditingTwoSectionView {
    private var header: some View {
        SectionHeaderView(
            title: title,
            isTitleLocalized: false
        )
    }
}

// MARK: - Photos:

private extension FileEditingTwoSectionView {
    private var photosContent: some View {
        LazyVGrid(
            columns: columns,
            alignment: .leading,
            spacing: spacing
        ) {
            photosItem
        }
    }
    
    private var photosItem: some View {
        ForEach(
            photos,
            content: photo
        )
    }
    
    private func photo(_ photo: NT_PhotoEditorPhoto) -> some View {
        ImageBackgroundTitleSubtitleView(
            image: image(photo),
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            isShowingImageBackground: false,
            imageCornerRadius: 12,
            title: title(photo),
            titleFont: .headline,
            titleAlignment: .leading,
            isShowingSubtitle: false,
            subtitle: "",
            subtitleFont: .subheadline,
            subtitleAlignment: .leading,
            titleSubtitleAlignment: .leading,
            titleSubtitleSpacing: 4,
            horizontalAlignment: .leading,
            spacing: 12,
            verticalPadding: photoPadding,
            horizontalPadding: photoPadding,
            maxHeight: .infinity,
            isShowingBackground: true,
            cornerRadius: 16,
            imageSingleTapAction: {
                select(photo)
            }
        )
    }
}

// MARK: - Preview:

#Preview {
    @Previewable @State var selectedPhoto: NT_PhotoEditorPhoto? = .example.first
    
    ScrollView {
        FileEditingTwoSectionView(
            section: .example.last!,
            selectedPhoto: $selectedPhoto
        )
    }
    .safeAreaPadding(
        .all,
        16
    )
    .safeAreaPadding(
        .bottom,
        16
    )
    .background(Color(.systemGroupedBackground))
    .localizedNavigationTitle(title: "Sunset")
    .navigationStack()
}
