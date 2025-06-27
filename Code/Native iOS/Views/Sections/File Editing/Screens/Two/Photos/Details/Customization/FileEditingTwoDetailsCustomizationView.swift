//
//  FileEditingTwoDetailsCustomizationView.swift
//  Native
//

import SwiftUI

struct FileEditingTwoDetailsCustomizationView: View {
    
    // MARK: - Private properties:
    
    /// Resolution of the image of the photo that is currently selected:
    @Binding private var selectedResolution: NT_ImageResolution
    
    /// Aspect ratio of the image of the photo that is currently selected:
    @Binding private var selectedAspectRatio: NT_ImageAspectRatio
    
    /// Grid of the image of the photo that is currently selected:
    @Binding private var selectedGrid: NT_ImageGrid
    
    /// Saturation of the image of the photo that is currently selected:
    @Binding private var selectedSaturation: Double
    
    /// Brightness of the image of the photo that is currently selected:
    @Binding private var selectedBrightness: Double
    
    init(
        selectedResolution: Binding<NT_ImageResolution>,
        selectedAspectRatio: Binding<NT_ImageAspectRatio>,
        selectedGrid: Binding<NT_ImageGrid>,
        selectedSaturation: Binding<Double>,
        selectedBrightness: Binding<Double>
    ) {
        
        /// Properties initialization:
        _selectedResolution = selectedResolution
        _selectedAspectRatio = selectedAspectRatio
        _selectedGrid = selectedGrid
        _selectedSaturation = selectedSaturation
        _selectedBrightness = selectedBrightness
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

private extension FileEditingTwoDetailsCustomizationView {
    private var item: some View {
        Section("Customization") {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        resolutionPicker
        aspectRatioPicker
        gridPicker
        saturationSlider
        brightnessSlider
    }
}

// MARK: - Resolution picker:

private extension FileEditingTwoDetailsCustomizationView {
    private var resolutionPicker: some View {
        Picker(selection: $selectedResolution) {
            resolutionsContent
        } label: {
            label("Resolution")
        }
    }
    
    private var resolutionsContent: some View {
        ForEach(
            resolutions,
            content: resolution
        )
    }
    
    private func resolution(_ resolution: NT_ImageResolution) -> some View {
        Text(title(resolution))
            .tag(resolution)
    }
}

// MARK: - Aspect ratio picker:

private extension FileEditingTwoDetailsCustomizationView {
    private var aspectRatioPicker: some View {
        Picker(selection: $selectedAspectRatio) {
            aspectRatiosContent
        } label: {
            label("Aspect Ratio")
        }
    }
    
    private var aspectRatiosContent: some View {
        ForEach(
            aspectRatios,
            content: aspectRatio
        )
    }
    
    private func aspectRatio(_ aspectRatio: NT_ImageAspectRatio) -> some View {
        Text(title(aspectRatio))
            .tag(aspectRatio)
    }
}

// MARK: - Grid picker:

private extension FileEditingTwoDetailsCustomizationView {
    private var gridPicker: some View {
        Picker(selection: $selectedGrid) {
            gridPickerItem
        } label: {
            label("Grid")
        }
    }
    
    @ViewBuilder
    private var gridPickerItem: some View {
        grid(.none)
        Divider()
        gridsContent
    }
    
    private var gridsContent: some View {
        ForEach(
            grids,
            content: grid
        )
    }
    
    private func grid(_ grid: NT_ImageGrid) -> some View {
        Text(title(grid))
            .tag(grid)
    }
}

// MARK: - Saturation slider:

private extension FileEditingTwoDetailsCustomizationView {
    private var saturationSlider: some View {
        Slider(
            value: $selectedSaturation,
            in: saturationBrightnessRange
        ) {
            label("Saturation")
        }
    }
}

// MARK: - Brightness slider:

private extension FileEditingTwoDetailsCustomizationView {
    private var brightnessSlider: some View {
        Slider(
            value: $selectedBrightness,
            in: saturationBrightnessRange
        ) {
            label("Brightness")
        }
    }
}

// MARK: - Label:

private extension FileEditingTwoDetailsCustomizationView {
    private func label(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(font)
            .multilineTextAlignment(.leading)
            .foregroundStyle(.primary)
    }
}

// MARK: - Preview:

#Preview {
    @Previewable @State var selectedResolution: NT_ImageResolution = .full
    @Previewable @State var selectedAspectRatio: NT_ImageAspectRatio = .sixteenByNine
    @Previewable @State var selectedGrid: NT_ImageGrid = .none
    @Previewable @State var selectedSaturation: Double = 0.3
    @Previewable @State var selectedBrightness: Double = 0.7
    
    List {
        FileEditingTwoDetailsCustomizationView(
            selectedResolution: $selectedResolution,
            selectedAspectRatio: $selectedAspectRatio,
            selectedGrid: $selectedGrid,
            selectedSaturation: $selectedSaturation,
            selectedBrightness: $selectedBrightness
        )
    }
    .listStyle(.insetGrouped)
    .localizedNavigationTitle(title: "Bright Sun")
    .navigationStack()
}
