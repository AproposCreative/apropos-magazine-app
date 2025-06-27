//
//  FileEditingTwoDetailsView.swift
//  Native
//

import SwiftUI

struct FileEditingTwoDetailsView: View {
    
    // MARK: - Properties:
    
    /// 'Bool' value indicating whether or not the photo editor is currently presented:
    @State var isPhotoEditorPresented: Bool = false
    
    /// An actual photo to display the details for:
    let photo: NT_PhotoEditorPhoto
    
    // MARK: - Private properties:
    
    /// Dismisses the view:
    @Environment(\.dismiss) private var dismiss
    
    /// Resolution of the image of the photo that is currently selected:
    @State private var selectedResolution: NT_ImageResolution = .full
    
    /// Aspect ratio of the image of the photo that is currently selected:
    @State private var selectedAspectRatio: NT_ImageAspectRatio = .sixteenByNine
    
    /// Grid of the image of the photo that is currently selected:
    @State private var selectedGrid: NT_ImageGrid = .none
    
    /// Saturation of the image of the photo that is currently selected:
    @State private var selectedSaturation: Double = 0.3
    
    /// Brightness of the image of the photo that is currently selected:
    @State private var selectedBrightness: Double = 0.7
    
    /// 'Bool' value indicating whether or not the photo should also be saved to the templates:
    @State private var isSavingToMyTemplates: Bool = true
    
    init(photo: NT_PhotoEditorPhoto) {
        
        /// Properties initialization:
        self.photo = photo
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        list
            .localizedNavigationTitle(
                title: title,
                isLocalized: false
            )
            .toolbarButton(
                title: "Cancel",
                font: .body,
                placement: .cancellationAction,
                action: dismiss.callAsFunction
            )
            .toolbarButton(
                title: "Create",
                action: create
            )
            .fullScreenCover(isPresented: $isPhotoEditorPresented) {
                FileEditingFiveView(photo: photo)
            }
            .navigationStack()
            .presentationDetents([.medium, .large])
    }
}

// MARK: - List:

private extension FileEditingTwoDetailsView {
    private var list: some View {
        listContent
            .listStyle(.insetGrouped)
    }
    
    private var listContent: some View {
        List {
            listItem
        }
    }
    
    @ViewBuilder
    private var listItem: some View {
        FileEditingTwoDetailsInformationView(photo: photo)
        customization
        FileEditingTwoDetailsSaveToMyTemplatesView(isSavingToMyTemplates: $isSavingToMyTemplates)
    }
}

// MARK: - Customization:

private extension FileEditingTwoDetailsView {
    private var customization: some View {
        FileEditingTwoDetailsCustomizationView(
            selectedResolution: $selectedResolution,
            selectedAspectRatio: $selectedAspectRatio,
            selectedGrid: $selectedGrid,
            selectedSaturation: $selectedSaturation,
            selectedBrightness: $selectedBrightness
        )
    }
}

// MARK: - Preview:

#Preview {
    FileEditingTwoDetailsView(photo: .example.first!)
}
