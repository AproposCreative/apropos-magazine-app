//
//  FileEditingTwoDetailsInformationView.swift
//  Native
//

import SwiftUI

struct FileEditingTwoDetailsInformationView: View {
    
    // MARK: - Properties:
    
    /// Photo to display the information for:
    let photo: NT_PhotoEditorPhoto
    
    init(photo: NT_PhotoEditorPhoto) {
        
        /// Properties initialization:
        self.photo = photo
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .headerProminence(.increased)
    }
}

// MARK: - Item:

private extension FileEditingTwoDetailsInformationView {
    private var item: some View {
        Section("Information") {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        titleContent
        sizeContent
        lastUpdatedContent
        createdByContent
    }
}

// MARK: - Information:

private extension FileEditingTwoDetailsInformationView {
    private var titleContent: some View {
        LabelView(
            title: "Title",
            isShowingBadge: true,
            badge: title,
            style: style
        )
    }
    
    private var sizeContent: some View {
        LabelView(
            title: "Size",
            isShowingBadge: true,
            badge: size,
            style: style
        )
    }
    
    private var lastUpdatedContent: some View {
        LabelView(
            title: "Last Updated",
            isShowingBadge: true,
            badge: lastUpdated,
            style: style
        )
    }
    
    private var createdByContent: some View {
        LabelView(
            title: "Created by",
            isShowingBadge: true,
            badge: createdBy,
            style: style
        )
    }
}

// MARK: - Preview:

#Preview {
    List {
        FileEditingTwoDetailsInformationView(photo: .example.first!)
    }
    .listStyle(.insetGrouped)
    .localizedNavigationTitle(title: "Bright Sun")
    .navigationStack()
}
