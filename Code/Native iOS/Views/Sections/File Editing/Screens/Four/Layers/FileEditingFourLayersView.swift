//
//  FileEditingFourLayersView.swift
//  Native
//

import SwiftUI

struct FileEditingFourLayersView: View {
    
    // MARK: - Properties:
    
    /// Dismisses the view:
    @Environment(\.dismiss) var dismiss
    
    /// Layer that is currently selected (Can be 'nil' or no layer at all):
    @Binding var selectedLayer: NT_DesignToolLayer?
    
    /// An actual file to display the layers for:
    let file: NT_DesignToolFile
    
    init(
        file: NT_DesignToolFile,
        selectedLayer: Binding<NT_DesignToolLayer?>
    ) {
        
        /// Properties initialization:
        self.file = file
        _selectedLayer = selectedLayer
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        list
            .overlay {
                noLayers
            }
            .localizedNavigationTitle(title: "Layers")
            .toolbarButton(
                title: "Done",
                action: dismiss.callAsFunction
            )
            .animation(
                .default,
                value: layers
            )
            .navigationStack()
            .presentationDetents([.medium, .large])
    }
}

// MARK: - No layers:

private extension FileEditingFourLayersView {
    private var noLayers: some View {
        noLayersContent
            .opacity(noLayersOpacity)
    }
    
    private var noLayersContent: some View {
        EmptyStateView(
            title: "No Layers",
            subtitle: "Just add a layer and it will appear here."
        )
    }
}

// MARK: - List:

private extension FileEditingFourLayersView {
    private var list: some View {
        listContent
            .listStyle(.insetGrouped)
    }
    
    private var listContent: some View {
        List(
            layers,
            children: \.sublayers,
            selection: $selectedLayer
        ) {
            layer($0)
        }
    }
    
    private func layer(_ layer: NT_DesignToolLayer) -> some View {
        Button {
            select(layer)
        } label: {
            layerLabel(layer)
        }
    }
    
    private func layerLabel(_ layer: NT_DesignToolLayer) -> some View {
        LabelView(
            icon: icon(layer),
            isShowingIconBackground: false,
            title: name(layer)
        )
    }
}

// MARK: - Preview:

#Preview {
    @Previewable @State var selectedLayer: NT_DesignToolLayer? = .example.first
    
    FileEditingFourLayersView(
        file: .example.first!,
        selectedLayer: $selectedLayer
    )
}
