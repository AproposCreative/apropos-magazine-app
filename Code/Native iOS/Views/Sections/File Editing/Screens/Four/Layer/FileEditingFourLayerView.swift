//
//  FileEditingFourLayerView.swift
//  Native
//

import SwiftUI

struct FileEditingFourLayerView: View {
    
    // MARK: - Properties:
    
    /// Layer that is currently selected (Can be 'nil' or no layer at all):
    @Binding var selectedLayer: NT_DesignToolLayer?
    
    /// An actual layer to display:
    let layer: NT_DesignToolLayer
    
    /// Current amount of the zoom into the content of the file that the layer is a part of:
    let currentZoom: Double
    
    init(
        layer: NT_DesignToolLayer,
        selectedLayer: Binding<NT_DesignToolLayer?>,
        currentZoom: Double
    ) {
        
        /// Properties initialization:
        self.layer = layer
        _selectedLayer = selectedLayer
        self.currentZoom = currentZoom
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .overlay(border)
            .rotationEffect(.init(degrees: rotation))
            .padding(
                paddingPosition,
                paddingAmount
            )
            .opacity(opacity)
            .contentShape(.rect)
            .overlay(selection)
            .onTapGesture {
                select()
            }
    }
}

// MARK: - Selection:

private extension FileEditingFourLayerView {
    @ViewBuilder
    private var selection: some View {
        if isSelected {
            selectionContent
        }
    }
    
    private var selectionContent: some View {
        SelectionView(
            width: fullWidth,
            height: fullHeight,
            currentZoom: currentZoom
        )
    }
}

// MARK: - Border:

private extension FileEditingFourLayerView {
    private var border: some View {
        RoundedRectangle(
            cornerRadius: cornerRadius,
            style: cornerStyle
        )
        .stroke(
            borderColor,
            lineWidth: borderWidth
        )
    }
}

// MARK: - Item:

private extension FileEditingFourLayerView {
    @ViewBuilder
    private var item: some View {
        switch type {
        case .shape (let shape): self.shape(shape)
        case .stack (let stack): self.stack(stack)
        }
    }
}

// MARK: - Shape:

private extension FileEditingFourLayerView {
    private func shape(_ shape: NT_DesignToolShape) -> some View {
        shapeContent(shape)
            .frame(
                width: width,
                height: height,
                alignment: genericAlignment
            )
    }
    
    @ViewBuilder
    private func shapeContent(_ shape: NT_DesignToolShape) -> some View {
        switch shape {
        case .capsule: capsule()
        case .circle: circle()
        case .ellipse: ellipse()
        case .path: path()
        case .rectangle: rectangle()
        case .roundedRectangle: roundedRectangle()
        }
    }
    
    private func capsule() -> some View {
        Capsule(style: cornerStyle)
            .gradientShadowFill(
                color: color,
                gradientStart: gradientStart,
                gradientEnd: gradientEnd,
                isGradient: isGradientFill,
                shadowColor: shadowColor,
                shadowRadius: shadowRadius,
                shadowXAxis: shadowXAxis,
                shadowYAxis: shadowYAxis,
                isMirroringShadow: isMirroringShadow,
                innerShadowColor: innerShadowColor,
                innerShadowRadius: innerShadowRadius,
                innerShadowXAxis: innerShadowXAxis,
                innerShadowYAxis: innerShadowYAxis,
                isMirroringInnerShadow: isMirroringInnerShadow
            )
    }
    
    private func circle() -> some View {
        Circle()
            .gradientShadowFill(
                color: color,
                gradientStart: gradientStart,
                gradientEnd: gradientEnd,
                isGradient: isGradientFill,
                shadowColor: shadowColor,
                shadowRadius: shadowRadius,
                shadowXAxis: shadowXAxis,
                shadowYAxis: shadowYAxis,
                isMirroringShadow: isMirroringShadow,
                innerShadowColor: innerShadowColor,
                innerShadowRadius: innerShadowRadius,
                innerShadowXAxis: innerShadowXAxis,
                innerShadowYAxis: innerShadowYAxis,
                isMirroringInnerShadow: isMirroringInnerShadow
            )
    }
    
    private func ellipse() -> some View {
        Ellipse()
            .gradientShadowFill(
                color: color,
                gradientStart: gradientStart,
                gradientEnd: gradientEnd,
                isGradient: isGradientFill,
                shadowColor: shadowColor,
                shadowRadius: shadowRadius,
                shadowXAxis: shadowXAxis,
                shadowYAxis: shadowYAxis,
                isMirroringShadow: isMirroringShadow,
                innerShadowColor: innerShadowColor,
                innerShadowRadius: innerShadowRadius,
                innerShadowXAxis: innerShadowXAxis,
                innerShadowYAxis: innerShadowYAxis,
                isMirroringInnerShadow: isMirroringInnerShadow
            )
    }
    
    private func path() -> some View {
        Path()
            .gradientShadowFill(
                color: color,
                gradientStart: gradientStart,
                gradientEnd: gradientEnd,
                isGradient: isGradientFill,
                shadowColor: shadowColor,
                shadowRadius: shadowRadius,
                shadowXAxis: shadowXAxis,
                shadowYAxis: shadowYAxis,
                isMirroringShadow: isMirroringShadow,
                innerShadowColor: innerShadowColor,
                innerShadowRadius: innerShadowRadius,
                innerShadowXAxis: innerShadowXAxis,
                innerShadowYAxis: innerShadowYAxis,
                isMirroringInnerShadow: isMirroringInnerShadow
            )
    }
    
    private func rectangle() -> some View {
        Rectangle()
            .gradientShadowFill(
                color: color,
                gradientStart: gradientStart,
                gradientEnd: gradientEnd,
                isGradient: isGradientFill,
                shadowColor: shadowColor,
                shadowRadius: shadowRadius,
                shadowXAxis: shadowXAxis,
                shadowYAxis: shadowYAxis,
                isMirroringShadow: isMirroringShadow,
                innerShadowColor: innerShadowColor,
                innerShadowRadius: innerShadowRadius,
                innerShadowXAxis: innerShadowXAxis,
                innerShadowYAxis: innerShadowYAxis,
                isMirroringInnerShadow: isMirroringInnerShadow
            )
    }
    
    private func roundedRectangle() -> some View {
        RoundedRectangle(
            cornerRadius: cornerRadius,
            style: cornerStyle
        )
        .gradientShadowFill(
            color: color,
            gradientStart: gradientStart,
            gradientEnd: gradientEnd,
            isGradient: isGradientFill,
            shadowColor: shadowColor,
            shadowRadius: shadowRadius,
            shadowXAxis: shadowXAxis,
            shadowYAxis: shadowYAxis,
            isMirroringShadow: isMirroringShadow,
            innerShadowColor: innerShadowColor,
            innerShadowRadius: innerShadowRadius,
            innerShadowXAxis: innerShadowXAxis,
            innerShadowYAxis: innerShadowYAxis,
            isMirroringInnerShadow: isMirroringInnerShadow
        )
    }
}

// MARK: - Stack:

private extension FileEditingFourLayerView {
    @ViewBuilder
    private func stack(_ stack: NT_DesignToolStack) -> some View {
        if !isSublayersEmpty {
            stackItem(stack)
        }
    }
    
    private func stackItem(_ stack: NT_DesignToolStack) -> some View {
        stackItemContent(stack)
            .frame(
                width: width,
                height: height,
                alignment: genericAlignment
            )
            .background(roundedRectangle())
    }
    
    @ViewBuilder
    private func stackItemContent(_ stack: NT_DesignToolStack) -> some View {
        switch stack {
        case .depth: depthStack()
        case .vertical: verticalStack()
        case .horizontal: horizontalStack()
        }
    }
    
    private func depthStack() -> some View {
        ZStack(alignment: genericAlignment) {
            sublayersContent
        }
    }
    
    private func verticalStack() -> some View {
        VStack(
            alignment: horizontalAlignment,
            spacing: spacing
        ) {
            sublayersContent
        }
    }
    
    private func horizontalStack() -> some View {
        HStack(
            alignment: verticalAlignment,
            spacing: spacing
        ) {
            sublayersContent
        }
    }
}

// MARK: - Sub-layers:

private extension FileEditingFourLayerView {
    private var sublayersContent: some View {
        ForEach(
            sublayers,
            content: sublayerContent
        )
    }
    
    private func sublayerContent(_ sublayer: NT_DesignToolLayer) -> some View {
        FileEditingFourLayerView(
            layer: sublayer,
            selectedLayer: $selectedLayer,
            currentZoom: currentZoom
        )
    }
}

// MARK: - Preview:

#Preview {
    @Previewable @State var selectedLayer: NT_DesignToolLayer? = .example.first
    
    FileEditingFourLayerView(
        layer: .example.first!,
        selectedLayer: $selectedLayer,
        currentZoom: 1
    )
    .padding()
}
