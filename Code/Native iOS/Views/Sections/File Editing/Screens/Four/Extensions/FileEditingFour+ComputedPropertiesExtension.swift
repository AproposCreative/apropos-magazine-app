//
//  FileEditingFour+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension FileEditingFourView {
    
    // MARK: - Computed properties:
    
    /// An array of all of the layers that are part of the file (We are reversing an array of all of the layers because this method appends the layers into an array of all of the layers to return in a reverse order if any given layer has the sub-layers that are part of it):
    var layers: [NT_DesignToolLayer] {
        flattenLayers(file.layers).reversed()
    }
    
    /// An array of the types of the layer to select from:
    var layerTypes: [NT_DesignToolLayerType] {
        NT_DesignToolLayerType.allTypes
    }
    
    /// 'Bool' value indicating whether or not an array of the layers to display is empty:
    var isLayersEmpty: Bool {
        layers.isEmpty
    }
    
    /// Title of the file:
    var title: String {
        file.title
    }
    
    /// Font of the buttons that are displayed on the view:
    var buttonFont: Font {
        .body
    }
    
    /// Symbol variant of the icons of the buttons that are displayed on the view:
    var buttonIconSymbolVariant: SymbolVariants {
        .none
    }
    
    /// Current amount of the zoom into the content of the file:
    var currentZoom: Double {
        scale * magnification
    }

    /// Gesture to let the users zoom into the content of the file:
    var zoomGesture: _EndedGesture<GestureStateGesture<MagnificationGesture, CGFloat>> {
        MagnificationGesture()
            .updating($magnification) { value, state, _ in
                
                /// Firstly making sure that the value isn't less than the minimum scale of the zoom that is allowed:
                guard !value.isLess(than: zoomMinScale) else { return }
                
                /// If yes, then updating the state of the gesture with the given value:
                state = value
            }
            .onEnded { value in
                
                /// Firstly getting the new scale based on the given value:
                let newScale: Double = scale * value
                
                /// Then getting the scale based on the new scale and its minimum and maximum values:
                let scale: Double = min(
                    max(
                        newScale,
                        zoomMinScale
                    ),
                    zoomMaxScale
                )
                
                /// Lastly updating the scale with the given scale:
                self.scale = scale
            }
    }
    
    /// Size of the icon of the 'Add Layer' menu:
    var addLayerIconSize: NT_IconSize {
        .custom(
            font: buttonFont,
            nonBackgroundFont: buttonFont,
            frame: 28,
            cornerRadius: 0,
            cornerStyle: .continuous
        )
    }
    
    /// Style of the buttons that are displayed on the view:
    var buttonStyle: NT_LabelStyle {
        .iconOnly
    }
    
    // MARK: - Private computed properties:

    /// Minimum scale of the zoom that is allowed:
    private var zoomMinScale: Double {
        0.5
    }

    /// Maximum scale of the zoom that is allowed:
    private var zoomMaxScale: Double {
        2
    }
}
