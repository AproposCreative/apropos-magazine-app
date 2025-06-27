//
//  FileEditingFourView.swift
//  Native
//

import SwiftUI

struct FileEditingFourView: View {
    
    // MARK: - Properties:
    
    /// 'Bool' value indicating whether or not the screen with all of the layers of the file is currently presented:
    @State var isLayersPresented: Bool = false
    
    /// Scale of the content of the file which is needed for the zoom:
    @State var scale: CGFloat = 1
    
    /// Layer that is currently selected (Can be 'nil' or no layer at all):
    @State var selectedLayer: NT_DesignToolLayer? = nil
    
    /// State of the magnification gesture which is needed for the zoom:
    @GestureState var magnification: CGFloat = 1
    
    /// An actual file to edit:
    let file: NT_DesignToolFile
    
    // MARK: - Private properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be embedded into the 'Navigation Stack':
    private let isEmbeddingIntoNavigationStack: Bool
    
    init(
        file: NT_DesignToolFile,
        isEmbeddingIntoNavigationStack: Bool = true
    ) {
        
        /// Properties initialization:
        self.file = file
        self.isEmbeddingIntoNavigationStack = isEmbeddingIntoNavigationStack
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        layersContent
            .localizedNavigationTitle(
                title: title,
                isLocalized: false
            )
            .toolbarButton(
                title: "Layers",
                icon: Icons.listBullet,
                iconSymbolVariant: buttonIconSymbolVariant,
                font: buttonFont,
                style: buttonStyle,
                isDisabled: isLayersEmpty,
                action: showLayers
            )
            .toolbar {
                editToolbar
            }
            .sheet(
                isPresented: $isLayersPresented,
                content: showLayers
            )
            .animation(
                .default,
                value: selectedLayer
            )
            .animation(
                .default,
                value: currentZoom
            )
            .navigationStack(isEmbedding: isEmbeddingIntoNavigationStack)
    }
}

// MARK: - Layers:

private extension FileEditingFourView {
    private var layersContent: some View {
        layersItem
            .scaleEffect(currentZoom)
            .gesture(zoomGesture)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Layers")
    }
    
    private var layersItem: some View {
        ZStack {
            layersItemContent
        }
    }
    
    private var layersItemContent: some View {
        ForEach(
            layers,
            content: layer
        )
    }
    
    private func layer(_ layer: NT_DesignToolLayer) -> some View {
        FileEditingFourLayerView(
            layer: layer,
            selectedLayer: $selectedLayer,
            currentZoom: currentZoom
        )
    }
}

// MARK: - Edit toolbar:

private extension FileEditingFourView {
    private var editToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            editToolbarContent
        }
    }
    
    @ViewBuilder
    private var editToolbarContent: some View {
        addLayerMenu
        Spacer()
        groupButton
        Spacer()
        customizeButton
        Spacer()
        selectButton
        Spacer()
        generateButton
    }
}

// MARK: - Add layer menu:

private extension FileEditingFourView {
    private var addLayerMenu: some View {
        Menu {
            layerTypesContent
        } label: {
            addLayerLabel
        }
    }
    
    private var addLayerLabel: some View {
        LabelView(
            icon: Icons.plusCircle,
            iconSymbolVariant: buttonIconSymbolVariant,
            iconSize: addLayerIconSize,
            title: "Add Layer",
            titleFont: buttonFont
        )
    }
    
    private var layerTypesContent: some View {
        ForEach(
            layerTypes,
            id: \.title,
            content: type
        )
    }
    
    private func type(_ type: NT_DesignToolLayerType) -> some View {
        ButtonView(
            title: title(type),
            icon: icon(type),
            iconSymbolVariant: buttonIconSymbolVariant,
            iconFont: buttonFont,
            style: .titleAndIcon
        ) {
            addNewLayer(type)
        }
    }
}

// MARK: - Buttons:

private extension FileEditingFourView {    
    private var groupButton: some View {
        ButtonView(
            title: "Group",
            icon: Icons.rectangleStack,
            iconSymbolVariant: buttonIconSymbolVariant,
            iconFont: buttonFont,
            style: buttonStyle,
            action: group
        )
    }
    
    private var customizeButton: some View {
        ButtonView(
            title: "Customize",
            icon: Icons.paintbrush,
            iconSymbolVariant: buttonIconSymbolVariant,
            iconFont: buttonFont,
            style: buttonStyle,
            action: customize
        )
    }
    
    private var selectButton: some View {
        ButtonView(
            title: "Select",
            icon: Icons.selectionPinInOut,
            iconSymbolVariant: buttonIconSymbolVariant,
            iconFont: buttonFont,
            style: buttonStyle,
            action: select
        )
    }
    
    private var generateButton: some View {
        ButtonView(
            title: "Generate",
            icon: Icons.sparkles,
            iconSymbolVariant: buttonIconSymbolVariant,
            iconFont: buttonFont,
            style: buttonStyle,
            action: generate
        )
    }
}

// MARK: - Layers:

private extension FileEditingFourView {
    private func showLayers() -> some View {
        FileEditingFourLayersView(
            file: file,
            selectedLayer: $selectedLayer
        )
    }
}

// MARK: - Preview:

#Preview {
    FileEditingFourView(
        file: .example.first!,
        isEmbeddingIntoNavigationStack: true
    )
}
