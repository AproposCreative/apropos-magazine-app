//
//  FileEditingFiveView.swift
//  Native
//

import SwiftUI

struct FileEditingFiveView: View {
    
    // MARK: - Properties:
    
    /// Angle of the rotation of the image if applicable:
    @State var rotationAngle: Angle = .zero
    
    /// An actual photo to edit:
    let photo: NT_PhotoEditorPhoto
    
    // MARK: - Private properties:
    
    /// Dismisses the view:
    @Environment(\.dismiss) private var dismiss
    
    init(photo: NT_PhotoEditorPhoto) {
        
        /// Properties initialization:
        self.photo = photo
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        imageContent
            .localizedNavigationTitle(
                title: title,
                isLocalized: false
            )
            .toolbarButton(
                title: "Done",
                action: dismiss.callAsFunction
            )
            .toolbar {
                editToolbar
            }
            .animation(
                .default,
                value: rotationAngle
            )
            .navigationStack()
    }
}

// MARK: - Image:

private extension FileEditingFiveView {
    private var imageContent: some View {
        image
            .resizable()
            .scaledToFit()
            .roundedCorners(cornerRadius: 16)
            .rotationEffect(rotationAngle)
            .padding()
            .accessibilityLabel("Photo to edit")
    }
}

// MARK: - Edit toolbar:

private extension FileEditingFiveView {
    private var editToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            editToolbarContent
        }
    }
    
    @ViewBuilder
    private var editToolbarContent: some View {
        newImageButton
        Spacer()
        annotateButton
        Spacer()
        cropButton
        Spacer()
        rotateLeftButton
        Spacer()
        rotateRightButton
    }
}

// MARK: - Buttons:

private extension FileEditingFiveView {
    private var newImageButton: some View {
        ButtonView(
            title: "New Image",
            icon: Icons.plusCircle,
            iconSymbolVariant: buttonIconSymbolVariant,
            iconFont: buttonFont,
            style: buttonStyle,
            action: newImage
        )
    }
    
    private var annotateButton: some View {
        ButtonView(
            title: "Annotate",
            icon: Icons.pencil,
            iconSymbolVariant: buttonIconSymbolVariant,
            iconFont: buttonFont,
            style: buttonStyle,
            action: annotate
        )
    }
    
    private var cropButton: some View {
        ButtonView(
            title: "Crop",
            icon: Icons.crop,
            iconSymbolVariant: buttonIconSymbolVariant,
            iconFont: buttonFont,
            style: buttonStyle,
            action: crop
        )
    }
    
    private var rotateLeftButton: some View {
        ButtonView(
            title: "Rotate Left",
            icon: Icons.rotateLeft,
            iconSymbolVariant: buttonIconSymbolVariant,
            iconFont: buttonFont,
            style: buttonStyle,
            action: rotateLeft
        )
    }
    
    private var rotateRightButton: some View {
        ButtonView(
            title: "Rotate Right",
            icon: Icons.rotateRight,
            iconSymbolVariant: buttonIconSymbolVariant,
            iconFont: buttonFont,
            style: buttonStyle,
            action: rotateRight
        )
    }
}

// MARK: - Preview:

#Preview {
    FileEditingFiveView(photo: .example.first!)
}
