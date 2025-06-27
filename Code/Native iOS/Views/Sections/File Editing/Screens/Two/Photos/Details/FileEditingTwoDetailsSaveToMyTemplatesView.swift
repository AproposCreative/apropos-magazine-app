//
//  FileEditingTwoDetailsSaveToMyTemplatesView.swift
//  Native
//

import SwiftUI

struct FileEditingTwoDetailsSaveToMyTemplatesView: View {
    
    // MARK: - Private properties:
    
    /// 'Bool' value indicating whether or not the photo should also be saved to the templates:
    @Binding private var isSavingToMyTemplates: Bool
    
    init(isSavingToMyTemplates: Binding<Bool>) {
        
        /// Properties initialization:
        _isSavingToMyTemplates = isSavingToMyTemplates
    }
    
    // MARK: - View:
    
    var body: some View {
        Section {
            item
        }
    }
}

// MARK: - Item:

private extension FileEditingTwoDetailsSaveToMyTemplatesView {
    private var item: some View {
        itemContent
            .font(.headline)
    }
    
    private var itemContent: some View {
        Toggle(
            "Save to My Templates",
            isOn: $isSavingToMyTemplates
        )
    }
}

// MARK: - Preview:

#Preview {
    @Previewable @State var isSavingToMyTemplates: Bool = false
    
    List {
        FileEditingTwoDetailsSaveToMyTemplatesView(isSavingToMyTemplates: $isSavingToMyTemplates)
    }
    .listStyle(.insetGrouped)
    .localizedNavigationTitle(title: "Bright Sun")
    .navigationStack()
}
