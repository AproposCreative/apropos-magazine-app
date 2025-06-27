//
//  FileEditingFourLayer+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension FileEditingFourLayerView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not an array of the sub-layers of the layer is empty:
    var isSublayersEmpty: Bool {
        sublayers.isEmpty
    }
    
    /// 'Bool' value indicating whether or not the layer is currently selected:
    var isSelected: Bool {
        selectedLayer == layer
    }
    
    /// An array of the sub-layers of the layer to display:
    var sublayers: [NT_DesignToolLayer] {
        layer.sublayers ?? []
    }
    
    /// Identifier of the layer:
    var identifier: String {
        layer.id
    }
    
    /// Type of the layer:
    var type: NT_DesignToolLayerType {
        layer.type
    }
    
    /// Full width of the layer (Needed to get the width of the stack with its content for when the layer is selected):
    var fullWidth: Double {
        layer.fullWidth()
    }
    
    /// Full height of the layer (Needed to get the height of the stack with its content for when the layer is selected):
    var fullHeight: Double {
        layer.fullHeight()
    }
    
    /// Width of the layer if applicable:
    var width: CGFloat? {
        if let width: Double = layer.width {
            return .init(width)
        } else {
            return nil
        }
    }
    
    /// Height of the layer if applicable:
    var height: CGFloat? {
        if let height: Double = layer.height {
            return .init(height)
        } else {
            return nil
        }
    }
    
    /// Fill of the layer:
    var fill: NT_DesignToolFill {
        layer.fill
    }
    
    /// 'Bool' value indicating whether or not the layer has the fill applied to it:
    var doesHaveFill: Bool {
        fill != .none
    }
    
    /// 'Bool' value indicating whether or not the layer has a gradient fill:
    var isGradientFill: Bool {
        layer.fill == .gradient
    }
    
    /// Color of the layer:
    var color: Color {
        layer.colorContent
    }
    
    /// Starting color of the gradient of the layer if applicable:
    var gradientStart: Color {
        layer.gradientStartContent
    }
    
    /// Ending color of the gradient of the layer if applicable:
    var gradientEnd: Color {
        layer.gradientEndContent
    }
    
    /// Radius of the rounded corners of the layer:
    var cornerRadius: Double {
        layer.cornerRadius
    }
    
    /// Style of the rounded corners of the layer:
    var cornerStyle: RoundedCornerStyle {
        layer.cornerStyle
    }
    
    /// Width of the border of the layer:
    var borderWidth: Double {
        layer.borderWidth
    }
    
    /// Color of the border of the layer:
    var borderColor: Color {
        layer.borderColor
    }
    
    /// Color of the shadow of the layer:
    var shadowColor: Color {
        layer.shadowColor
    }
    
    /// Radius of the shadow of the layer:
    var shadowRadius: Double {
        layer.shadowRadius
    }
    
    /// X-axis value of the shadow of the layer:
    var shadowXAxis: Double {
        layer.shadowXAxis
    }
    
    /// Y-axis value of the shadow of the layer:
    var shadowYAxis: Double {
        layer.shadowYAxis
    }
    
    /// 'Bool' value indicating whether or not the shadow of the layer should be mirrored onto the opposite side of the layer too:
    var isMirroringShadow: Bool {
        layer.isMirroringShadow
    }
    
    /// Color of the inner shadow of the layer:
    var innerShadowColor: Color {
        layer.innerShadowColor
    }
    
    /// Radius of the inner shadow of the layer:
    var innerShadowRadius: Double {
        layer.innerShadowRadius
    }
    
    /// X-axis value of the inner shadow of the layer:
    var innerShadowXAxis: Double {
        layer.innerShadowXAxis
    }
    
    /// Y-axis value of the inner shadow of the layer:
    var innerShadowYAxis: Double {
        layer.innerShadowYAxis
    }
    
    /// 'Bool' value indicating whether or not the inner shadow of the layer should be mirrored onto the opposite side of the layer too:
    var isMirroringInnerShadow: Bool {
        layer.isMirroringInnerShadow
    }
    
    /// Generic alignment of the layer (Only applicable to the depth stacks):
    var genericAlignment: Alignment {
        switch alignment {
        case .generic (let type):
            switch type {
            case .center:
                return .center
            case .leading:
                return .leading
            case .trailing:
                return .trailing
            case .top:
                return .top
            case .bottom:
                return .bottom
            case .topLeading:
                return .topLeading
            case .bottomLeading:
                return .bottomLeading
            case .topTrailing:
                return .topTrailing
            case .bottomTrailing:
                return .bottomTrailing
            }
        case .horizontal (_),
                .vertical (_):
            return .center
        }
    }
    
    /// Horizontal alignment of the layer (Only applicable to the vertical stacks):
    var horizontalAlignment: HorizontalAlignment {
        switch alignment {
        case .horizontal (let type):
            switch type {
            case .leading:
                return .leading
            case .center:
                return .center
            case .trailing:
                return .trailing
            }
        case .generic (_),
                .vertical (_):
            return .center
        }
    }
    
    /// Vertical alignment of the layer (Only applicable to the horizontal stacks):
    var verticalAlignment: VerticalAlignment {
        switch alignment {
        case .vertical (let type):
            switch type {
            case .top:
                return .top
            case .center:
                return .center
            case .bottom:
                return .bottom
            case .firstTextBaseline:
                return .firstTextBaseline
            case .lastTextBaseline:
                return .lastTextBaseline
            }
        case .generic (_),
                .horizontal (_):
            return .center
        }
    }
    
    /// Spacing between the content of the layer:
    var spacing: Double {
        layer.spacing
    }
    
    /// Angle of the rotation of the layer:
    var rotation: Double {
        layer.rotation
    }
    
    /// Position of the padding:
    var paddingPosition: Edge.Set {
        switch padding.position {
        case .none: return []
        case .all: return .all
        case .horizontal: return .horizontal
        case .vertical: return .vertical
        case .top: return .top
        case .leading: return .leading
        case .bottom: return .bottom
        case .trailing: return .trailing
        }
    }
    
    /// Amount of the padding:
    var paddingAmount: Double {
        padding.amount
    }
    
    /// Opacity of the layer:
    var opacity: Double {
        layer.opacity
    }
    
    // MARK: - Private computed properties:
    
    /// Alignment of the layer if applicable:
    private var alignment: NT_DesignToolAlignment {
        layer.alignment
    }
    
    /// Padding of the layer:
    private var padding: NT_DesignToolPadding {
        layer.padding
    }
}
