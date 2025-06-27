//
//  NT_DesignToolLayer.swift
//  Native
//

import SwiftUI

struct NT_DesignToolLayer {
    
    // MARK: - Properties:
    
    /// Identifier of the layer:
    let id: String
    
    /// Name of the layer:
    let name: String
    
    /// Type of the layer:
    let type: NT_DesignToolLayerType
    
    /// Frame of the layer:
    let frame: NT_DesignToolFrame
    
    /// Fill of the layer if applicable:
    let fill: NT_DesignToolFill
    
    /// Color of the layer:
    let color: String
    
    /// Starting color of the gradient of the layer if applicable:
    let gradientStart: String
    
    /// Ending color of the gradient of the layer if applicable:
    let gradientEnd: String
    
    /// Opacity of the fill color of the layer:
    let fillOpacity: Double
    
    /// Corners of the layer:
    let corners: NT_DesignToolCorners
    
    /// Border of the layer:
    let border: NT_DesignToolBorder
    
    /// Shadow of the layer:
    let shadow: NT_DesignToolShadow
    
    /// Inner shadow of the layer:
    let innerShadow: NT_DesignToolShadow
    
    /// Alignment of the layer:
    let alignment: NT_DesignToolAlignment
    
    /// Spacing between the sub-layers of the layer:
    let spacing: Double
    
    /// Padding of the layer:
    let padding: NT_DesignToolPadding
    
    /// Opacity of the layer:
    let opacity: Double
    
    /// Angle of the rotation of the layer:
    let rotation: Double
    
    /// An array of the sub-layers that are part of the layer:
    let sublayers: [NT_DesignToolLayer]?
    
    init(
        id: String,
        name: String,
        type: NT_DesignToolLayerType,
        frame: NT_DesignToolFrame,
        fill: NT_DesignToolFill,
        color: String,
        gradientStart: String,
        gradientEnd: String,
        fillOpacity: Double,
        corners: NT_DesignToolCorners,
        border: NT_DesignToolBorder,
        shadow: NT_DesignToolShadow,
        innerShadow: NT_DesignToolShadow,
        alignment: NT_DesignToolAlignment,
        spacing: Double,
        padding: NT_DesignToolPadding,
        opacity: Double,
        rotation: Double,
        sublayers: [NT_DesignToolLayer]?
    ) {
        
        /// Properties initialization:
        self.id = id
        self.name = name
        self.type = type
        self.frame = frame
        self.fill = fill
        self.color = color
        self.gradientStart = gradientStart
        self.gradientEnd = gradientEnd
        self.fillOpacity = fillOpacity
        self.corners = corners
        self.border = border
        self.shadow = shadow
        self.innerShadow = innerShadow
        self.alignment = alignment
        self.spacing = spacing
        self.padding = padding
        self.opacity = opacity
        self.rotation = rotation
        self.sublayers = sublayers
    }
    
    // MARK: - Computed properties:
    
    /// Width of the layer if applicable:
    var width: Double? {
        frame.width
    }
    
    /// Height of the layer if applicable:
    var height: Double? {
        frame.height
    }
    
    /// Content of the color of the layer:
    var colorContent: Color {
        .init(color).opacity(fillOpacity)
    }
    
    /// Content of the starting color of the gradient of the layer if applicable:
    var gradientStartContent: Color {
        .init(gradientStart).opacity(fillOpacity)
    }
    
    /// Content of the ending color of the gradient of the layer if applicable:
    var gradientEndContent: Color {
        .init(gradientEnd).opacity(fillOpacity)
    }
    
    /// Radius of the corners of the layer:
    var cornerRadius: Double {
        corners.radius
    }
    
    /// Style of the corners of the layer:
    var cornerStyle: RoundedCornerStyle {
        corners.style
    }
    
    /// Width of the border of the layer:
    var borderWidth: Double {
        border.width
    }
    
    /// Color of the border of the layer:
    var borderColor: Color {
        .init(border.color).opacity(borderOpacity)
    }
    
    /// Opacity of the color of the border of the layer:
    var borderOpacity: Double {
        border.opacity
    }
    
    /// Color of the shadow of the layer:
    var shadowColor: Color {
        .init(shadow.color).opacity(shadowOpacity)
    }
    
    /// Opacity of the color of the shadow of the layer:
    var shadowOpacity: Double {
        shadow.opacity
    }
    
    /// Radius of the shadow of the layer:
    var shadowRadius: Double {
        shadow.radius
    }
    
    /// X-axis value of the shadow of the layer:
    var shadowXAxis: Double {
        shadow.xAxis
    }
    
    /// Y-axis value of the shadow of the layer:
    var shadowYAxis: Double {
        shadow.yAxis
    }
    
    /// 'Bool' value indicating whether or not the shadow of the layer should be mirrored onto the opposite side of the layer too:
    var isMirroringShadow: Bool {
        shadow.isMirroring
    }
    
    /// Color of the inner shadow of the layer:
    var innerShadowColor: Color {
        .init(innerShadow.color).opacity(innerShadowOpacity)
    }
    
    /// Opacity of the color of the inner shadow of the layer:
    var innerShadowOpacity: Double {
        innerShadow.opacity
    }
    
    /// Radius of the inner shadow of the layer:
    var innerShadowRadius: Double {
        innerShadow.radius
    }
    
    /// X-axis value of the inner shadow of the layer:
    var innerShadowXAxis: Double {
        innerShadow.xAxis
    }
    
    /// Y-axis value of the inner shadow of the layer:
    var innerShadowYAxis: Double {
        innerShadow.yAxis
    }
    
    /// 'Bool' value indicating whether or not the inner shadow of the layer should be mirrored onto the opposite side of the layer too:
    var isMirroringInnerShadow: Bool {
        innerShadow.isMirroring
    }
    
    /// Position of the padding of the layer:
    var paddingPosition: NT_DesignToolPaddingPosition {
        padding.position
    }
    
    /// Amount of the padding of the layer:
    var paddingAmount: Double {
        padding.amount
    }
    
    /// Icon of the layer that is based on whether or not it has the sub-layers
    var icon: String {
        sublayers == nil ? Icons.rectangle : Icons.rectangleStack
    }
    
    // MARK: - Functions:
    
    /// Returns the full width of the layer:
    func fullWidth() -> Double {
        if let width {
            return .init(width)
        } else {
            switch type {
            case .shape (_):
                return 0
            case .stack(let stack):
                if let sublayers,
                   !sublayers.isEmpty {
                    switch stack {
                    case .depth,
                            .vertical:
                        return .init(sublayers.compactMap { $0.width }.max() ?? 0)
                    case .horizontal:
                        return .init((sublayers.compactMap { $0.width }.reduce(0, +)) + (.init(sublayers.count - 1) * spacing) + (.init(paddingPosition.count) * paddingAmount))
                    }
                } else {
                    return 0
                }
            }
        }
    }
    
    /// Returns the full height of the layer:
    func fullHeight() -> Double {
        if let height {
            return .init(height)
        } else {
            switch type {
            case .shape (_):
                return 0
            case .stack(let stack):
                if let sublayers,
                   !sublayers.isEmpty {
                    switch stack {
                    case .depth,
                            .horizontal:
                        return .init(sublayers.compactMap { $0.height }.max() ?? 0)
                    case .vertical:
                        return .init((sublayers.compactMap { $0.height }.reduce(0, +)) + (.init(sublayers.count - 1) * spacing) + (.init(paddingPosition.count) * paddingAmount))
                    }
                } else {
                    return 0
                }
            }
        }
    }
}

// MARK: - Identifiable:

extension NT_DesignToolLayer: Identifiable {  }

// MARK: - Equatable:

extension NT_DesignToolLayer: Equatable {  }

// MARK: - Hashable:

extension NT_DesignToolLayer: Hashable {  }

// MARK: - Codable:

extension NT_DesignToolLayer: Codable {  }

// MARK: - Example:

extension NT_DesignToolLayer {
    
    // MARK: - Computed properties:
    
    /// An array of the example layers:
    static var example: [NT_DesignToolLayer] {
        [
            .init(
                id: "Item.1",
                name: "Illustration",
                type: .stack(.depth),
                frame: .init(
                    width: 360,
                    height: 400
                ),
                fill: .gradient,
                color: Colors.blue,
                gradientStart: Colors.blueGradientStart,
                gradientEnd: Colors.blueGradientEnd,
                fillOpacity: 1,
                corners: .init(
                    radius: 36,
                    type: .continuous
                ),
                border: .init(
                    width: 0,
                    color: Colors.transparent,
                    opacity: 1
                ),
                shadow: .init(
                    color: Colors.transparent,
                    opacity: 1,
                    radius: 0,
                    xAxis: 0,
                    yAxis: 0,
                    isMirroring: false
                ),
                innerShadow: .init(
                    color: Colors.transparent,
                    opacity: 1,
                    radius: 0,
                    xAxis: 0,
                    yAxis: 0,
                    isMirroring: false
                ),
                alignment: .generic(.center),
                spacing: 0,
                padding: .init(
                    position: .all,
                    amount: 16
                ),
                opacity: 1,
                rotation: 0,
                sublayers: [
                    .init(
                        id: "Item.2",
                        name: "Content",
                        type: .stack(.vertical),
                        frame: .init(
                            width: 256,
                            height: 312
                        ),
                        fill: .solid,
                        color: Colors.light,
                        gradientStart: Colors.transparent,
                        gradientEnd: Colors.transparent,
                        fillOpacity: 1,
                        corners: .init(
                            radius: 24,
                            type: .continuous
                        ),
                        border: .init(
                            width: 0,
                            color: Colors.transparent,
                            opacity: 1
                        ),
                        shadow: .init(
                            color: Colors.blue,
                            opacity: 0.64,
                            radius: 16,
                            xAxis: 0,
                            yAxis: 16,
                            isMirroring: false
                        ),
                        innerShadow: .init(
                            color: Colors.blue,
                            opacity: 0.64,
                            radius: 4,
                            xAxis: 0,
                            yAxis: -4,
                            isMirroring: false
                        ),
                        alignment: .horizontal(.leading),
                        spacing: 8,
                        padding: .init(
                            position: .none,
                            amount: 0
                        ),
                        opacity: 1,
                        rotation: 0,
                        sublayers: [
                            .init(
                                id: "Item.3",
                                name: "Item - 1",
                                type: .stack(.horizontal),
                                frame: .init(
                                    width: nil,
                                    height: nil
                                ),
                                fill: .none,
                                color: Colors.transparent,
                                gradientStart: Colors.transparent,
                                gradientEnd: Colors.transparent,
                                fillOpacity: 1,
                                corners: .init(
                                    radius: 0,
                                    type: .continuous
                                ),
                                border: .init(
                                    width: 0,
                                    color: Colors.transparent,
                                    opacity: 1
                                ),
                                shadow: .init(
                                    color: Colors.transparent,
                                    opacity: 1,
                                    radius: 0,
                                    xAxis: 0,
                                    yAxis: 0,
                                    isMirroring: false
                                ),
                                innerShadow: .init(
                                    color: Colors.transparent,
                                    opacity: 1,
                                    radius: 0,
                                    xAxis: 0,
                                    yAxis: 0,
                                    isMirroring: false
                                ),
                                alignment: .vertical(.center),
                                spacing: 8,
                                padding: .init(
                                    position: .none,
                                    amount: 0
                                ),
                                opacity: 1,
                                rotation: 0,
                                sublayers: [
                                    .init(
                                        id: "Item.4",
                                        name: "Item - 1",
                                        type: .shape(.roundedRectangle),
                                        frame: .init(
                                            width: 64,
                                            height: 10
                                        ),
                                        fill: .gradient,
                                        color: Colors.blue,
                                        gradientStart: Colors.blueGradientStart,
                                        gradientEnd: Colors.blueGradientEnd,
                                        fillOpacity: 1,
                                        corners: .init(
                                            radius: 5,
                                            type: .continuous
                                        ),
                                        border: .init(
                                            width: 0,
                                            color: Colors.transparent,
                                            opacity: 1
                                        ),
                                        shadow: .init(
                                            color: Colors.transparent,
                                            opacity: 1,
                                            radius: 0,
                                            xAxis: 0,
                                            yAxis: 0,
                                            isMirroring: false
                                        ),
                                        innerShadow: .init(
                                            color: Colors.blue,
                                            opacity: 0.64,
                                            radius: 2,
                                            xAxis: 2,
                                            yAxis: 2,
                                            isMirroring: true
                                        ),
                                        alignment: .generic(.center),
                                        spacing: 0,
                                        padding: .init(
                                            position: .none,
                                            amount: 0
                                        ),
                                        opacity: 1,
                                        rotation: 0,
                                        sublayers: nil
                                    ),
                                    .init(
                                        id: "Item.5",
                                        name: "Item - 2",
                                        type: .shape(.roundedRectangle),
                                        frame: .init(
                                            width: 32,
                                            height: 10
                                        ),
                                        fill: .gradient,
                                        color: Colors.orange,
                                        gradientStart: Colors.orangeGradientStart,
                                        gradientEnd: Colors.orangeGradientEnd,
                                        fillOpacity: 1,
                                        corners: .init(
                                            radius: 5,
                                            type: .continuous
                                        ),
                                        border: .init(
                                            width: 0,
                                            color: Colors.transparent,
                                            opacity: 1
                                        ),
                                        shadow: .init(
                                            color: Colors.transparent,
                                            opacity: 1,
                                            radius: 0,
                                            xAxis: 0,
                                            yAxis: 0,
                                            isMirroring: false
                                        ),
                                        innerShadow: .init(
                                            color: Colors.orange,
                                            opacity: 0.64,
                                            radius: 2,
                                            xAxis: 2,
                                            yAxis: 2,
                                            isMirroring: true
                                        ),
                                        alignment: .generic(.center),
                                        spacing: 0,
                                        padding: .init(
                                            position: .none,
                                            amount: 0
                                        ),
                                        opacity: 1,
                                        rotation: 0,
                                        sublayers: nil
                                    ),
                                    .init(
                                        id: "Item.6",
                                        name: "Item - 3",
                                        type: .shape(.roundedRectangle),
                                        frame: .init(
                                            width: 48,
                                            height: 10
                                        ),
                                        fill: .gradient,
                                        color: Colors.purple,
                                        gradientStart: Colors.purpleGradientStart,
                                        gradientEnd: Colors.purpleGradientEnd,
                                        fillOpacity: 1,
                                        corners: .init(
                                            radius: 5,
                                            type: .continuous
                                        ),
                                        border: .init(
                                            width: 0,
                                            color: Colors.transparent,
                                            opacity: 1
                                        ),
                                        shadow: .init(
                                            color: Colors.transparent,
                                            opacity: 1,
                                            radius: 0,
                                            xAxis: 0,
                                            yAxis: 0,
                                            isMirroring: false
                                        ),
                                        innerShadow: .init(
                                            color: Colors.purple,
                                            opacity: 0.64,
                                            radius: 2,
                                            xAxis: 2,
                                            yAxis: 2,
                                            isMirroring: true
                                        ),
                                        alignment: .generic(.center),
                                        spacing: 0,
                                        padding: .init(
                                            position: .none,
                                            amount: 0
                                        ),
                                        opacity: 1,
                                        rotation: 0,
                                        sublayers: nil
                                    ),
                                    .init(
                                        id: "Item.7",
                                        name: "Item - 4",
                                        type: .shape(.roundedRectangle),
                                        frame: .init(
                                            width: 24,
                                            height: 10
                                        ),
                                        fill: .gradient,
                                        color: Colors.pink,
                                        gradientStart: Colors.pinkGradientStart,
                                        gradientEnd: Colors.pinkGradientEnd,
                                        fillOpacity: 1,
                                        corners: .init(
                                            radius: 5,
                                            type: .continuous
                                        ),
                                        border: .init(
                                            width: 0,
                                            color: Colors.transparent,
                                            opacity: 1
                                        ),
                                        shadow: .init(
                                            color: Colors.transparent,
                                            opacity: 1,
                                            radius: 0,
                                            xAxis: 0,
                                            yAxis: 0,
                                            isMirroring: false
                                        ),
                                        innerShadow: .init(
                                            color: Colors.pink,
                                            opacity: 0.64,
                                            radius: 2,
                                            xAxis: 2,
                                            yAxis: 2,
                                            isMirroring: true
                                        ),
                                        alignment: .generic(.center),
                                        spacing: 0,
                                        padding: .init(
                                            position: .none,
                                            amount: 0
                                        ),
                                        opacity: 1,
                                        rotation: 0,
                                        sublayers: nil
                                    )
                                ]
                            ),
                            .init(
                                id: "Item.8",
                                name: "Item - 2",
                                type: .stack(.horizontal),
                                frame: .init(
                                    width: nil,
                                    height: nil
                                ),
                                fill: .none,
                                color: Colors.transparent,
                                gradientStart: Colors.transparent,
                                gradientEnd: Colors.transparent,
                                fillOpacity: 1,
                                corners: .init(
                                    radius: 0,
                                    type: .continuous
                                ),
                                border: .init(
                                    width: 0,
                                    color: Colors.transparent,
                                    opacity: 1
                                ),
                                shadow: .init(
                                    color: Colors.transparent,
                                    opacity: 1,
                                    radius: 0,
                                    xAxis: 0,
                                    yAxis: 0,
                                    isMirroring: false
                                ),
                                innerShadow: .init(
                                    color: Colors.transparent,
                                    opacity: 1,
                                    radius: 0,
                                    xAxis: 0,
                                    yAxis: 0,
                                    isMirroring: false
                                ),
                                alignment: .vertical(.center),
                                spacing: 8,
                                padding: .init(
                                    position: .none,
                                    amount: 0
                                ),
                                opacity: 1,
                                rotation: 0,
                                sublayers: [
                                    .init(
                                        id: "Item.9",
                                        name: "Item - 1",
                                        type: .shape(.roundedRectangle),
                                        frame: .init(
                                            width: 144,
                                            height: 10
                                        ),
                                        fill: .gradient,
                                        color: Colors.green,
                                        gradientStart: Colors.greenGradientStart,
                                        gradientEnd: Colors.greenGradientEnd,
                                        fillOpacity: 1,
                                        corners: .init(
                                            radius: 5,
                                            type: .continuous
                                        ),
                                        border: .init(
                                            width: 0,
                                            color: Colors.transparent,
                                            opacity: 1
                                        ),
                                        shadow: .init(
                                            color: Colors.transparent,
                                            opacity: 1,
                                            radius: 0,
                                            xAxis: 0,
                                            yAxis: 0,
                                            isMirroring: false
                                        ),
                                        innerShadow: .init(
                                            color: Colors.green,
                                            opacity: 0.64,
                                            radius: 2,
                                            xAxis: 2,
                                            yAxis: 2,
                                            isMirroring: true
                                        ),
                                        alignment: .generic(.center),
                                        spacing: 0,
                                        padding: .init(
                                            position: .none,
                                            amount: 0
                                        ),
                                        opacity: 1,
                                        rotation: 0,
                                        sublayers: nil
                                    ),
                                    .init(
                                        id: "Item.10",
                                        name: "Item - 2",
                                        type: .shape(.roundedRectangle),
                                        frame: .init(
                                            width: 64,
                                            height: 10
                                        ),
                                        fill: .gradient,
                                        color: Colors.blue,
                                        gradientStart: Colors.blueGradientStart,
                                        gradientEnd: Colors.blueGradientEnd,
                                        fillOpacity: 1,
                                        corners: .init(
                                            radius: 5,
                                            type: .continuous
                                        ),
                                        border: .init(
                                            width: 0,
                                            color: Colors.transparent,
                                            opacity: 1
                                        ),
                                        shadow: .init(
                                            color: Colors.transparent,
                                            opacity: 1,
                                            radius: 0,
                                            xAxis: 0,
                                            yAxis: 0,
                                            isMirroring: false
                                        ),
                                        innerShadow: .init(
                                            color: Colors.blue,
                                            opacity: 0.64,
                                            radius: 2,
                                            xAxis: 2,
                                            yAxis: 2,
                                            isMirroring: true
                                        ),
                                        alignment: .generic(.center),
                                        spacing: 0,
                                        padding: .init(
                                            position: .none,
                                            amount: 0
                                        ),
                                        opacity: 1,
                                        rotation: 0,
                                        sublayers: nil
                                    )
                                ]
                            ),
                            .init(
                                id: "Item.11",
                                name: "Item - 3",
                                type: .stack(.horizontal),
                                frame: .init(
                                    width: nil,
                                    height: nil
                                ),
                                fill: .none,
                                color: Colors.transparent,
                                gradientStart: Colors.transparent,
                                gradientEnd: Colors.transparent,
                                fillOpacity: 1,
                                corners: .init(
                                    radius: 0,
                                    type: .continuous
                                ),
                                border: .init(
                                    width: 0,
                                    color: Colors.transparent,
                                    opacity: 1
                                ),
                                shadow: .init(
                                    color: Colors.transparent,
                                    opacity: 1,
                                    radius: 0,
                                    xAxis: 0,
                                    yAxis: 0,
                                    isMirroring: false
                                ),
                                innerShadow: .init(
                                    color: Colors.transparent,
                                    opacity: 1,
                                    radius: 0,
                                    xAxis: 0,
                                    yAxis: 0,
                                    isMirroring: false
                                ),
                                alignment: .vertical(.center),
                                spacing: 8,
                                padding: .init(
                                    position: .none,
                                    amount: 0
                                ),
                                opacity: 1,
                                rotation: 0,
                                sublayers: [
                                    .init(
                                        id: "Item.12",
                                        name: "Item - 1",
                                        type: .shape(.roundedRectangle),
                                        frame: .init(
                                            width: 96,
                                            height: 10
                                        ),
                                        fill: .gradient,
                                        color: Colors.orange,
                                        gradientStart: Colors.orangeGradientStart,
                                        gradientEnd: Colors.orangeGradientEnd,
                                        fillOpacity: 1,
                                        corners: .init(
                                            radius: 5,
                                            type: .continuous
                                        ),
                                        border: .init(
                                            width: 0,
                                            color: Colors.transparent,
                                            opacity: 1
                                        ),
                                        shadow: .init(
                                            color: Colors.transparent,
                                            opacity: 1,
                                            radius: 0,
                                            xAxis: 0,
                                            yAxis: 0,
                                            isMirroring: false
                                        ),
                                        innerShadow: .init(
                                            color: Colors.orange,
                                            opacity: 0.64,
                                            radius: 2,
                                            xAxis: 2,
                                            yAxis: 2,
                                            isMirroring: true
                                        ),
                                        alignment: .generic(.center),
                                        spacing: 0,
                                        padding: .init(
                                            position: .none,
                                            amount: 0
                                        ),
                                        opacity: 1,
                                        rotation: 0,
                                        sublayers: nil
                                    ),
                                    .init(
                                        id: "Item.13",
                                        name: "Item - 2",
                                        type: .shape(.roundedRectangle),
                                        frame: .init(
                                            width: 32,
                                            height: 10
                                        ),
                                        fill: .gradient,
                                        color: Colors.purple,
                                        gradientStart: Colors.purpleGradientStart,
                                        gradientEnd: Colors.purpleGradientEnd,
                                        fillOpacity: 1,
                                        corners: .init(
                                            radius: 5,
                                            type: .continuous
                                        ),
                                        border: .init(
                                            width: 0,
                                            color: Colors.transparent,
                                            opacity: 1
                                        ),
                                        shadow: .init(
                                            color: Colors.transparent,
                                            opacity: 1,
                                            radius: 0,
                                            xAxis: 0,
                                            yAxis: 0,
                                            isMirroring: false
                                        ),
                                        innerShadow: .init(
                                            color: Colors.purple,
                                            opacity: 0.64,
                                            radius: 2,
                                            xAxis: 2,
                                            yAxis: 2,
                                            isMirroring: true
                                        ),
                                        alignment: .generic(.center),
                                        spacing: 0,
                                        padding: .init(
                                            position: .none,
                                            amount: 0
                                        ),
                                        opacity: 1,
                                        rotation: 0,
                                        sublayers: nil
                                    ),
                                    .init(
                                        id: "Item.14",
                                        name: "Item - 3",
                                        type: .shape(.roundedRectangle),
                                        frame: .init(
                                            width: 80,
                                            height: 10
                                        ),
                                        fill: .gradient,
                                        color: Colors.pink,
                                        gradientStart: Colors.pinkGradientStart,
                                        gradientEnd: Colors.pinkGradientEnd,
                                        fillOpacity: 1,
                                        corners: .init(
                                            radius: 5,
                                            type: .continuous
                                        ),
                                        border: .init(
                                            width: 0,
                                            color: Colors.transparent,
                                            opacity: 1
                                        ),
                                        shadow: .init(
                                            color: Colors.transparent,
                                            opacity: 1,
                                            radius: 0,
                                            xAxis: 0,
                                            yAxis: 0,
                                            isMirroring: false
                                        ),
                                        innerShadow: .init(
                                            color: Colors.pink,
                                            opacity: 0.64,
                                            radius: 2,
                                            xAxis: 2,
                                            yAxis: 2,
                                            isMirroring: true
                                        ),
                                        alignment: .generic(.center),
                                        spacing: 0,
                                        padding: .init(
                                            position: .none,
                                            amount: 0
                                        ),
                                        opacity: 1,
                                        rotation: 0,
                                        sublayers: nil
                                    )
                                ]
                            ),
                            .init(
                                id: "Item.15",
                                name: "Item - 4",
                                type: .stack(.horizontal),
                                frame: .init(
                                    width: nil,
                                    height: nil
                                ),
                                fill: .none,
                                color: Colors.transparent,
                                gradientStart: Colors.transparent,
                                gradientEnd: Colors.transparent,
                                fillOpacity: 1,
                                corners: .init(
                                    radius: 0,
                                    type: .continuous
                                ),
                                border: .init(
                                    width: 0,
                                    color: Colors.transparent,
                                    opacity: 1
                                ),
                                shadow: .init(
                                    color: Colors.transparent,
                                    opacity: 1,
                                    radius: 0,
                                    xAxis: 0,
                                    yAxis: 0,
                                    isMirroring: false
                                ),
                                innerShadow: .init(
                                    color: Colors.transparent,
                                    opacity: 1,
                                    radius: 0,
                                    xAxis: 0,
                                    yAxis: 0,
                                    isMirroring: false
                                ),
                                alignment: .vertical(.center),
                                spacing: 8,
                                padding: .init(
                                    position: .none,
                                    amount: 0
                                ),
                                opacity: 1,
                                rotation: 0,
                                sublayers: [
                                    .init(
                                        id: "Item.16",
                                        name: "Item - 1",
                                        type: .shape(.roundedRectangle),
                                        frame: .init(
                                            width: 32,
                                            height: 10
                                        ),
                                        fill: .gradient,
                                        color: Colors.green,
                                        gradientStart: Colors.greenGradientStart,
                                        gradientEnd: Colors.greenGradientEnd,
                                        fillOpacity: 1,
                                        corners: .init(
                                            radius: 5,
                                            type: .continuous
                                        ),
                                        border: .init(
                                            width: 0,
                                            color: Colors.transparent,
                                            opacity: 1
                                        ),
                                        shadow: .init(
                                            color: Colors.transparent,
                                            opacity: 1,
                                            radius: 0,
                                            xAxis: 0,
                                            yAxis: 0,
                                            isMirroring: false
                                        ),
                                        innerShadow: .init(
                                            color: Colors.green,
                                            opacity: 0.64,
                                            radius: 2,
                                            xAxis: 2,
                                            yAxis: 2,
                                            isMirroring: true
                                        ),
                                        alignment: .generic(.center),
                                        spacing: 0,
                                        padding: .init(
                                            position: .none,
                                            amount: 0
                                        ),
                                        opacity: 1,
                                        rotation: 0,
                                        sublayers: nil
                                    ),
                                    .init(
                                        id: "Item.17",
                                        name: "Item - 2",
                                        type: .shape(.roundedRectangle),
                                        frame: .init(
                                            width: 64,
                                            height: 10
                                        ),
                                        fill: .gradient,
                                        color: Colors.blue,
                                        gradientStart: Colors.blueGradientStart,
                                        gradientEnd: Colors.blueGradientEnd,
                                        fillOpacity: 1,
                                        corners: .init(
                                            radius: 5,
                                            type: .continuous
                                        ),
                                        border: .init(
                                            width: 0,
                                            color: Colors.transparent,
                                            opacity: 1
                                        ),
                                        shadow: .init(
                                            color: Colors.transparent,
                                            opacity: 1,
                                            radius: 0,
                                            xAxis: 0,
                                            yAxis: 0,
                                            isMirroring: false
                                        ),
                                        innerShadow: .init(
                                            color: Colors.blue,
                                            opacity: 0.64,
                                            radius: 2,
                                            xAxis: 2,
                                            yAxis: 2,
                                            isMirroring: true
                                        ),
                                        alignment: .generic(.center),
                                        spacing: 0,
                                        padding: .init(
                                            position: .none,
                                            amount: 0
                                        ),
                                        opacity: 1,
                                        rotation: 0,
                                        sublayers: nil
                                    ),
                                    .init(
                                        id: "Item.18",
                                        name: "Item - 3",
                                        type: .shape(.roundedRectangle),
                                        frame: .init(
                                            width: 48,
                                            height: 10
                                        ),
                                        fill: .gradient,
                                        color: Colors.orange,
                                        gradientStart: Colors.orangeGradientStart,
                                        gradientEnd: Colors.orangeGradientEnd,
                                        fillOpacity: 1,
                                        corners: .init(
                                            radius: 5,
                                            type: .continuous
                                        ),
                                        border: .init(
                                            width: 0,
                                            color: Colors.transparent,
                                            opacity: 1
                                        ),
                                        shadow: .init(
                                            color: Colors.transparent,
                                            opacity: 1,
                                            radius: 0,
                                            xAxis: 0,
                                            yAxis: 0,
                                            isMirroring: false
                                        ),
                                        innerShadow: .init(
                                            color: Colors.orange,
                                            opacity: 0.64,
                                            radius: 2,
                                            xAxis: 2,
                                            yAxis: 2,
                                            isMirroring: true
                                        ),
                                        alignment: .generic(.center),
                                        spacing: 0,
                                        padding: .init(
                                            position: .none,
                                            amount: 0
                                        ),
                                        opacity: 1,
                                        rotation: 0,
                                        sublayers: nil
                                    )
                                ]
                            ),
                            .init(
                                id: "Item.19",
                                name: "Item - 5",
                                type: .shape(.roundedRectangle),
                                frame: .init(
                                    width: 200,
                                    height: 10
                                ),
                                fill: .gradient,
                                color: Colors.purple,
                                gradientStart: Colors.purpleGradientStart,
                                gradientEnd: Colors.purpleGradientEnd,
                                fillOpacity: 1,
                                corners: .init(
                                    radius: 5,
                                    type: .continuous
                                ),
                                border: .init(
                                    width: 0,
                                    color: Colors.transparent,
                                    opacity: 1
                                ),
                                shadow: .init(
                                    color: Colors.transparent,
                                    opacity: 1,
                                    radius: 0,
                                    xAxis: 0,
                                    yAxis: 0,
                                    isMirroring: false
                                ),
                                innerShadow: .init(
                                    color: Colors.purple,
                                    opacity: 0.64,
                                    radius: 2,
                                    xAxis: 2,
                                    yAxis: 2,
                                    isMirroring: true
                                ),
                                alignment: .generic(.center),
                                spacing: 0,
                                padding: .init(
                                    position: .none,
                                    amount: 0
                                ),
                                opacity: 1,
                                rotation: 0,
                                sublayers: nil
                            ),
                            .init(
                                id: "Item.20",
                                name: "Item - 6",
                                type: .stack(.horizontal),
                                frame: .init(
                                    width: nil,
                                    height: nil
                                ),
                                fill: .none,
                                color: Colors.transparent,
                                gradientStart: Colors.transparent,
                                gradientEnd: Colors.transparent,
                                fillOpacity: 1,
                                corners: .init(
                                    radius: 0,
                                    type: .continuous
                                ),
                                border: .init(
                                    width: 0,
                                    color: Colors.transparent,
                                    opacity: 1
                                ),
                                shadow: .init(
                                    color: Colors.transparent,
                                    opacity: 1,
                                    radius: 0,
                                    xAxis: 0,
                                    yAxis: 0,
                                    isMirroring: false
                                ),
                                innerShadow: .init(
                                    color: Colors.transparent,
                                    opacity: 1,
                                    radius: 0,
                                    xAxis: 0,
                                    yAxis: 0,
                                    isMirroring: false
                                ),
                                alignment: .vertical(.center),
                                spacing: 8,
                                padding: .init(
                                    position: .none,
                                    amount: 0
                                ),
                                opacity: 1,
                                rotation: 0,
                                sublayers: [
                                    .init(
                                        id: "Item.21",
                                        name: "Item - 1",
                                        type: .shape(.roundedRectangle),
                                        frame: .init(
                                            width: 48,
                                            height: 10
                                        ),
                                        fill: .gradient,
                                        color: Colors.pink,
                                        gradientStart: Colors.pinkGradientStart,
                                        gradientEnd: Colors.pinkGradientEnd,
                                        fillOpacity: 1,
                                        corners: .init(
                                            radius: 5,
                                            type: .continuous
                                        ),
                                        border: .init(
                                            width: 0,
                                            color: Colors.transparent,
                                            opacity: 1
                                        ),
                                        shadow: .init(
                                            color: Colors.transparent,
                                            opacity: 1,
                                            radius: 0,
                                            xAxis: 0,
                                            yAxis: 0,
                                            isMirroring: false
                                        ),
                                        innerShadow: .init(
                                            color: Colors.pink,
                                            opacity: 0.64,
                                            radius: 2,
                                            xAxis: 2,
                                            yAxis: 2,
                                            isMirroring: true
                                        ),
                                        alignment: .generic(.center),
                                        spacing: 0,
                                        padding: .init(
                                            position: .none,
                                            amount: 0
                                        ),
                                        opacity: 1,
                                        rotation: 0,
                                        sublayers: nil
                                    ),
                                    .init(
                                        id: "Item.22",
                                        name: "Item - 2",
                                        type: .shape(.roundedRectangle),
                                        frame: .init(
                                            width: 120,
                                            height: 10
                                        ),
                                        fill: .gradient,
                                        color: Colors.green,
                                        gradientStart: Colors.greenGradientStart,
                                        gradientEnd: Colors.greenGradientEnd,
                                        fillOpacity: 1,
                                        corners: .init(
                                            radius: 5,
                                            type: .continuous
                                        ),
                                        border: .init(
                                            width: 0,
                                            color: Colors.transparent,
                                            opacity: 1
                                        ),
                                        shadow: .init(
                                            color: Colors.transparent,
                                            opacity: 1,
                                            radius: 0,
                                            xAxis: 0,
                                            yAxis: 0,
                                            isMirroring: false
                                        ),
                                        innerShadow: .init(
                                            color: Colors.green,
                                            opacity: 0.64,
                                            radius: 2,
                                            xAxis: 2,
                                            yAxis: 2,
                                            isMirroring: true
                                        ),
                                        alignment: .generic(.center),
                                        spacing: 0,
                                        padding: .init(
                                            position: .none,
                                            amount: 0
                                        ),
                                        opacity: 1,
                                        rotation: 0,
                                        sublayers: nil
                                    )
                                ]
                            ),
                            .init(
                                id: "Item.23",
                                name: "Item - 7",
                                type: .stack(.horizontal),
                                frame: .init(
                                    width: nil,
                                    height: nil
                                ),
                                fill: .none,
                                color: Colors.transparent,
                                gradientStart: Colors.transparent,
                                gradientEnd: Colors.transparent,
                                fillOpacity: 1,
                                corners: .init(
                                    radius: 0,
                                    type: .continuous
                                ),
                                border: .init(
                                    width: 0,
                                    color: Colors.transparent,
                                    opacity: 1
                                ),
                                shadow: .init(
                                    color: Colors.transparent,
                                    opacity: 1,
                                    radius: 0,
                                    xAxis: 0,
                                    yAxis: 0,
                                    isMirroring: false
                                ),
                                innerShadow: .init(
                                    color: Colors.transparent,
                                    opacity: 1,
                                    radius: 0,
                                    xAxis: 0,
                                    yAxis: 0,
                                    isMirroring: false
                                ),
                                alignment: .vertical(.center),
                                spacing: 8,
                                padding: .init(
                                    position: .none,
                                    amount: 0
                                ),
                                opacity: 1,
                                rotation: 0,
                                sublayers: [
                                    .init(
                                        id: "Item.24",
                                        name: "Item - 1",
                                        type: .shape(.roundedRectangle),
                                        frame: .init(
                                            width: 24,
                                            height: 10
                                        ),
                                        fill: .gradient,
                                        color: Colors.blue,
                                        gradientStart: Colors.blueGradientStart,
                                        gradientEnd: Colors.blueGradientEnd,
                                        fillOpacity: 1,
                                        corners: .init(
                                            radius: 5,
                                            type: .continuous
                                        ),
                                        border: .init(
                                            width: 0,
                                            color: Colors.transparent,
                                            opacity: 1
                                        ),
                                        shadow: .init(
                                            color: Colors.transparent,
                                            opacity: 1,
                                            radius: 0,
                                            xAxis: 0,
                                            yAxis: 0,
                                            isMirroring: false
                                        ),
                                        innerShadow: .init(
                                            color: Colors.blue,
                                            opacity: 0.64,
                                            radius: 2,
                                            xAxis: 2,
                                            yAxis: 2,
                                            isMirroring: true
                                        ),
                                        alignment: .generic(.center),
                                        spacing: 0,
                                        padding: .init(
                                            position: .none,
                                            amount: 0
                                        ),
                                        opacity: 1,
                                        rotation: 0,
                                        sublayers: nil
                                    ),
                                    .init(
                                        id: "Item.25",
                                        name: "Item - 2",
                                        type: .shape(.roundedRectangle),
                                        frame: .init(
                                            width: 80,
                                            height: 10
                                        ),
                                        fill: .gradient,
                                        color: Colors.orange,
                                        gradientStart: Colors.orangeGradientStart,
                                        gradientEnd: Colors.orangeGradientEnd,
                                        fillOpacity: 1,
                                        corners: .init(
                                            radius: 5,
                                            type: .continuous
                                        ),
                                        border: .init(
                                            width: 0,
                                            color: Colors.transparent,
                                            opacity: 1
                                        ),
                                        shadow: .init(
                                            color: Colors.transparent,
                                            opacity: 1,
                                            radius: 0,
                                            xAxis: 0,
                                            yAxis: 0,
                                            isMirroring: false
                                        ),
                                        innerShadow: .init(
                                            color: Colors.orange,
                                            opacity: 0.64,
                                            radius: 2,
                                            xAxis: 2,
                                            yAxis: 2,
                                            isMirroring: true
                                        ),
                                        alignment: .generic(.center),
                                        spacing: 0,
                                        padding: .init(
                                            position: .none,
                                            amount: 0
                                        ),
                                        opacity: 1,
                                        rotation: 0,
                                        sublayers: nil
                                    ),
                                    .init(
                                        id: "Item.26",
                                        name: "Item - 3",
                                        type: .shape(.roundedRectangle),
                                        frame: .init(
                                            width: 32,
                                            height: 10
                                        ),
                                        fill: .gradient,
                                        color: Colors.purple,
                                        gradientStart: Colors.purpleGradientStart,
                                        gradientEnd: Colors.purpleGradientEnd,
                                        fillOpacity: 1,
                                        corners: .init(
                                            radius: 5,
                                            type: .continuous
                                        ),
                                        border: .init(
                                            width: 0,
                                            color: Colors.transparent,
                                            opacity: 1
                                        ),
                                        shadow: .init(
                                            color: Colors.transparent,
                                            opacity: 1,
                                            radius: 0,
                                            xAxis: 0,
                                            yAxis: 0,
                                            isMirroring: false
                                        ),
                                        innerShadow: .init(
                                            color: Colors.purple,
                                            opacity: 0.64,
                                            radius: 2,
                                            xAxis: 2,
                                            yAxis: 2,
                                            isMirroring: true
                                        ),
                                        alignment: .generic(.center),
                                        spacing: 0,
                                        padding: .init(
                                            position: .none,
                                            amount: 0
                                        ),
                                        opacity: 1,
                                        rotation: 0,
                                        sublayers: nil
                                    ),
                                    .init(
                                        id: "Item.27",
                                        name: "Item - 4",
                                        type: .shape(.roundedRectangle),
                                        frame: .init(
                                            width: 64,
                                            height: 10
                                        ),
                                        fill: .gradient,
                                        color: Colors.pink,
                                        gradientStart: Colors.pinkGradientStart,
                                        gradientEnd: Colors.pinkGradientEnd,
                                        fillOpacity: 1,
                                        corners: .init(
                                            radius: 5,
                                            type: .continuous
                                        ),
                                        border: .init(
                                            width: 0,
                                            color: Colors.transparent,
                                            opacity: 1
                                        ),
                                        shadow: .init(
                                            color: Colors.transparent,
                                            opacity: 1,
                                            radius: 0,
                                            xAxis: 0,
                                            yAxis: 0,
                                            isMirroring: false
                                        ),
                                        innerShadow: .init(
                                            color: Colors.pink,
                                            opacity: 0.64,
                                            radius: 2,
                                            xAxis: 2,
                                            yAxis: 2,
                                            isMirroring: true
                                        ),
                                        alignment: .generic(.center),
                                        spacing: 0,
                                        padding: .init(
                                            position: .none,
                                            amount: 0
                                        ),
                                        opacity: 1,
                                        rotation: 0,
                                        sublayers: nil
                                    )
                                ]
                            ),
                            .init(
                                id: "Item.28",
                                name: "Item - 8",
                                type: .stack(.horizontal),
                                frame: .init(
                                    width: nil,
                                    height: nil
                                ),
                                fill: .none,
                                color: Colors.transparent,
                                gradientStart: Colors.transparent,
                                gradientEnd: Colors.transparent,
                                fillOpacity: 1,
                                corners: .init(
                                    radius: 0,
                                    type: .continuous
                                ),
                                border: .init(
                                    width: 0,
                                    color: Colors.transparent,
                                    opacity: 1
                                ),
                                shadow: .init(
                                    color: Colors.transparent,
                                    opacity: 1,
                                    radius: 0,
                                    xAxis: 0,
                                    yAxis: 0,
                                    isMirroring: false
                                ),
                                innerShadow: .init(
                                    color: Colors.transparent,
                                    opacity: 1,
                                    radius: 0,
                                    xAxis: 0,
                                    yAxis: 0,
                                    isMirroring: false
                                ),
                                alignment: .vertical(.center),
                                spacing: 8,
                                padding: .init(
                                    position: .none,
                                    amount: 0
                                ),
                                opacity: 1,
                                rotation: 0,
                                sublayers: [
                                    .init(
                                        id: "Item.29",
                                        name: "Item - 1",
                                        type: .shape(.roundedRectangle),
                                        frame: .init(
                                            width: 120,
                                            height: 10
                                        ),
                                        fill: .gradient,
                                        color: Colors.green,
                                        gradientStart: Colors.greenGradientStart,
                                        gradientEnd: Colors.greenGradientEnd,
                                        fillOpacity: 1,
                                        corners: .init(
                                            radius: 5,
                                            type: .continuous
                                        ),
                                        border: .init(
                                            width: 0,
                                            color: Colors.transparent,
                                            opacity: 1
                                        ),
                                        shadow: .init(
                                            color: Colors.transparent,
                                            opacity: 1,
                                            radius: 0,
                                            xAxis: 0,
                                            yAxis: 0,
                                            isMirroring: false
                                        ),
                                        innerShadow: .init(
                                            color: Colors.green,
                                            opacity: 0.64,
                                            radius: 2,
                                            xAxis: 2,
                                            yAxis: 2,
                                            isMirroring: true
                                        ),
                                        alignment: .generic(.center),
                                        spacing: 0,
                                        padding: .init(
                                            position: .none,
                                            amount: 0
                                        ),
                                        opacity: 1,
                                        rotation: 0,
                                        sublayers: nil
                                    ),
                                    .init(
                                        id: "Item.30",
                                        name: "Item - 2",
                                        type: .shape(.roundedRectangle),
                                        frame: .init(
                                            width: 32,
                                            height: 10
                                        ),
                                        fill: .gradient,
                                        color: Colors.blue,
                                        gradientStart: Colors.blueGradientStart,
                                        gradientEnd: Colors.blueGradientEnd,
                                        fillOpacity: 1,
                                        corners: .init(
                                            radius: 5,
                                            type: .continuous
                                        ),
                                        border: .init(
                                            width: 0,
                                            color: Colors.transparent,
                                            opacity: 1
                                        ),
                                        shadow: .init(
                                            color: Colors.transparent,
                                            opacity: 1,
                                            radius: 0,
                                            xAxis: 0,
                                            yAxis: 0,
                                            isMirroring: false
                                        ),
                                        innerShadow: .init(
                                            color: Colors.blue,
                                            opacity: 0.64,
                                            radius: 2,
                                            xAxis: 2,
                                            yAxis: 2,
                                            isMirroring: true
                                        ),
                                        alignment: .generic(.center),
                                        spacing: 0,
                                        padding: .init(
                                            position: .none,
                                            amount: 0
                                        ),
                                        opacity: 1,
                                        rotation: 0,
                                        sublayers: nil
                                    ),
                                    .init(
                                        id: "Item.31",
                                        name: "Item - 3",
                                        type: .shape(.roundedRectangle),
                                        frame: .init(
                                            width: 32,
                                            height: 10
                                        ),
                                        fill: .gradient,
                                        color: Colors.orange,
                                        gradientStart: Colors.orangeGradientStart,
                                        gradientEnd: Colors.orangeGradientEnd,
                                        fillOpacity: 1,
                                        corners: .init(
                                            radius: 5,
                                            type: .continuous
                                        ),
                                        border: .init(
                                            width: 0,
                                            color: Colors.transparent,
                                            opacity: 1
                                        ),
                                        shadow: .init(
                                            color: Colors.transparent,
                                            opacity: 1,
                                            radius: 0,
                                            xAxis: 0,
                                            yAxis: 0,
                                            isMirroring: false
                                        ),
                                        innerShadow: .init(
                                            color: Colors.orange,
                                            opacity: 0.64,
                                            radius: 2,
                                            xAxis: 2,
                                            yAxis: 2,
                                            isMirroring: true
                                        ),
                                        alignment: .generic(.center),
                                        spacing: 0,
                                        padding: .init(
                                            position: .none,
                                            amount: 0
                                        ),
                                        opacity: 1,
                                        rotation: 0,
                                        sublayers: nil
                                    )
                                ]
                            ),
                            .init(
                                id: "Item.32",
                                name: "Item - 9",
                                type: .stack(.horizontal),
                                frame: .init(
                                    width: nil,
                                    height: nil
                                ),
                                fill: .none,
                                color: Colors.transparent,
                                gradientStart: Colors.transparent,
                                gradientEnd: Colors.transparent,
                                fillOpacity: 1,
                                corners: .init(
                                    radius: 0,
                                    type: .continuous
                                ),
                                border: .init(
                                    width: 0,
                                    color: Colors.transparent,
                                    opacity: 1
                                ),
                                shadow: .init(
                                    color: Colors.transparent,
                                    opacity: 1,
                                    radius: 0,
                                    xAxis: 0,
                                    yAxis: 0,
                                    isMirroring: false
                                ),
                                innerShadow: .init(
                                    color: Colors.transparent,
                                    opacity: 1,
                                    radius: 0,
                                    xAxis: 0,
                                    yAxis: 0,
                                    isMirroring: false
                                ),
                                alignment: .vertical(.center),
                                spacing: 8,
                                padding: .init(
                                    position: .none,
                                    amount: 0
                                ),
                                opacity: 1,
                                rotation: 0,
                                sublayers: [
                                    .init(
                                        id: "Item.33",
                                        name: "Item - 1",
                                        type: .shape(.roundedRectangle),
                                        frame: .init(
                                            width: 80,
                                            height: 10
                                        ),
                                        fill: .gradient,
                                        color: Colors.purple,
                                        gradientStart: Colors.purpleGradientStart,
                                        gradientEnd: Colors.purpleGradientEnd,
                                        fillOpacity: 1,
                                        corners: .init(
                                            radius: 5,
                                            type: .continuous
                                        ),
                                        border: .init(
                                            width: 0,
                                            color: Colors.transparent,
                                            opacity: 1
                                        ),
                                        shadow: .init(
                                            color: Colors.transparent,
                                            opacity: 1,
                                            radius: 0,
                                            xAxis: 0,
                                            yAxis: 0,
                                            isMirroring: false
                                        ),
                                        innerShadow: .init(
                                            color: Colors.purple,
                                            opacity: 0.64,
                                            radius: 2,
                                            xAxis: 2,
                                            yAxis: 2,
                                            isMirroring: true
                                        ),
                                        alignment: .generic(.center),
                                        spacing: 0,
                                        padding: .init(
                                            position: .none,
                                            amount: 0
                                        ),
                                        opacity: 1,
                                        rotation: 0,
                                        sublayers: nil
                                    ),
                                    .init(
                                        id: "Item.34",
                                        name: "Item - 2",
                                        type: .shape(.roundedRectangle),
                                        frame: .init(
                                            width: 64,
                                            height: 10
                                        ),
                                        fill: .gradient,
                                        color: Colors.pink,
                                        gradientStart: Colors.pinkGradientStart,
                                        gradientEnd: Colors.pinkGradientEnd,
                                        fillOpacity: 1,
                                        corners: .init(
                                            radius: 5,
                                            type: .continuous
                                        ),
                                        border: .init(
                                            width: 0,
                                            color: Colors.transparent,
                                            opacity: 1
                                        ),
                                        shadow: .init(
                                            color: Colors.transparent,
                                            opacity: 1,
                                            radius: 0,
                                            xAxis: 0,
                                            yAxis: 0,
                                            isMirroring: false
                                        ),
                                        innerShadow: .init(
                                            color: Colors.pink,
                                            opacity: 0.64,
                                            radius: 2,
                                            xAxis: 2,
                                            yAxis: 2,
                                            isMirroring: true
                                        ),
                                        alignment: .generic(.center),
                                        spacing: 0,
                                        padding: .init(
                                            position: .none,
                                            amount: 0
                                        ),
                                        opacity: 1,
                                        rotation: 0,
                                        sublayers: nil
                                    )
                                ]
                            ),
                            .init(
                                id: "Item.35",
                                name: "Item - 10",
                                type: .shape(.roundedRectangle),
                                frame: .init(
                                    width: 120,
                                    height: 10
                                ),
                                fill: .gradient,
                                color: Colors.green,
                                gradientStart: Colors.greenGradientStart,
                                gradientEnd: Colors.greenGradientEnd,
                                fillOpacity: 1,
                                corners: .init(
                                    radius: 5,
                                    type: .continuous
                                ),
                                border: .init(
                                    width: 0,
                                    color: Colors.transparent,
                                    opacity: 1
                                ),
                                shadow: .init(
                                    color: Colors.transparent,
                                    opacity: 1,
                                    radius: 0,
                                    xAxis: 0,
                                    yAxis: 0,
                                    isMirroring: false
                                ),
                                innerShadow: .init(
                                    color: Colors.green,
                                    opacity: 0.64,
                                    radius: 2,
                                    xAxis: 2,
                                    yAxis: 2,
                                    isMirroring: true
                                ),
                                alignment: .generic(.center),
                                spacing: 0,
                                padding: .init(
                                    position: .none,
                                    amount: 0
                                ),
                                opacity: 1,
                                rotation: 0,
                                sublayers: nil
                            ),
                            .init(
                                id: "Item.36",
                                name: "Item - 11",
                                type: .stack(.horizontal),
                                frame: .init(
                                    width: nil,
                                    height: nil
                                ),
                                fill: .none,
                                color: Colors.transparent,
                                gradientStart: Colors.transparent,
                                gradientEnd: Colors.transparent,
                                fillOpacity: 1,
                                corners: .init(
                                    radius: 0,
                                    type: .continuous
                                ),
                                border: .init(
                                    width: 0,
                                    color: Colors.transparent,
                                    opacity: 1
                                ),
                                shadow: .init(
                                    color: Colors.transparent,
                                    opacity: 1,
                                    radius: 0,
                                    xAxis: 0,
                                    yAxis: 0,
                                    isMirroring: false
                                ),
                                innerShadow: .init(
                                    color: Colors.transparent,
                                    opacity: 1,
                                    radius: 0,
                                    xAxis: 0,
                                    yAxis: 0,
                                    isMirroring: false
                                ),
                                alignment: .vertical(.center),
                                spacing: 8,
                                padding: .init(
                                    position: .none,
                                    amount: 0
                                ),
                                opacity: 1,
                                rotation: 0,
                                sublayers: [
                                    .init(
                                        id: "Item.37",
                                        name: "Item - 1",
                                        type: .shape(.roundedRectangle),
                                        frame: .init(
                                            width: 96,
                                            height: 10
                                        ),
                                        fill: .gradient,
                                        color: Colors.blue,
                                        gradientStart: Colors.blueGradientStart,
                                        gradientEnd: Colors.blueGradientEnd,
                                        fillOpacity: 1,
                                        corners: .init(
                                            radius: 5,
                                            type: .continuous
                                        ),
                                        border: .init(
                                            width: 0,
                                            color: Colors.transparent,
                                            opacity: 1
                                        ),
                                        shadow: .init(
                                            color: Colors.transparent,
                                            opacity: 1,
                                            radius: 0,
                                            xAxis: 0,
                                            yAxis: 0,
                                            isMirroring: false
                                        ),
                                        innerShadow: .init(
                                            color: Colors.blue,
                                            opacity: 0.64,
                                            radius: 2,
                                            xAxis: 2,
                                            yAxis: 2,
                                            isMirroring: true
                                        ),
                                        alignment: .generic(.center),
                                        spacing: 0,
                                        padding: .init(
                                            position: .none,
                                            amount: 0
                                        ),
                                        opacity: 1,
                                        rotation: 0,
                                        sublayers: nil
                                    ),
                                    .init(
                                        id: "Item.38",
                                        name: "Item - 2",
                                        type: .shape(.roundedRectangle),
                                        frame: .init(
                                            width: 32,
                                            height: 10
                                        ),
                                        fill: .gradient,
                                        color: Colors.orange,
                                        gradientStart: Colors.orangeGradientStart,
                                        gradientEnd: Colors.orangeGradientEnd,
                                        fillOpacity: 1,
                                        corners: .init(
                                            radius: 5,
                                            type: .continuous
                                        ),
                                        border: .init(
                                            width: 0,
                                            color: Colors.transparent,
                                            opacity: 1
                                        ),
                                        shadow: .init(
                                            color: Colors.transparent,
                                            opacity: 1,
                                            radius: 0,
                                            xAxis: 0,
                                            yAxis: 0,
                                            isMirroring: false
                                        ),
                                        innerShadow: .init(
                                            color: Colors.orange,
                                            opacity: 0.64,
                                            radius: 2,
                                            xAxis: 2,
                                            yAxis: 2,
                                            isMirroring: true
                                        ),
                                        alignment: .generic(.center),
                                        spacing: 0,
                                        padding: .init(
                                            position: .none,
                                            amount: 0
                                        ),
                                        opacity: 1,
                                        rotation: 0,
                                        sublayers: nil
                                    ),
                                    .init(
                                        id: "Item.39",
                                        name: "Item - 3",
                                        type: .shape(.roundedRectangle),
                                        frame: .init(
                                            width: 80,
                                            height: 10
                                        ),
                                        fill: .gradient,
                                        color: Colors.purple,
                                        gradientStart: Colors.purpleGradientStart,
                                        gradientEnd: Colors.purpleGradientEnd,
                                        fillOpacity: 1,
                                        corners: .init(
                                            radius: 5,
                                            type: .continuous
                                        ),
                                        border: .init(
                                            width: 0,
                                            color: Colors.transparent,
                                            opacity: 1
                                        ),
                                        shadow: .init(
                                            color: Colors.transparent,
                                            opacity: 1,
                                            radius: 0,
                                            xAxis: 0,
                                            yAxis: 0,
                                            isMirroring: false
                                        ),
                                        innerShadow: .init(
                                            color: Colors.purple,
                                            opacity: 0.64,
                                            radius: 2,
                                            xAxis: 2,
                                            yAxis: 2,
                                            isMirroring: true
                                        ),
                                        alignment: .generic(.center),
                                        spacing: 0,
                                        padding: .init(
                                            position: .none,
                                            amount: 0
                                        ),
                                        opacity: 1,
                                        rotation: 0,
                                        sublayers: nil
                                    )
                                ]
                            ),
                            .init(
                                id: "Item.40",
                                name: "Item - 12",
                                type: .stack(.horizontal),
                                frame: .init(
                                    width: nil,
                                    height: nil
                                ),
                                fill: .none,
                                color: Colors.transparent,
                                gradientStart: Colors.transparent,
                                gradientEnd: Colors.transparent,
                                fillOpacity: 1,
                                corners: .init(
                                    radius: 0,
                                    type: .continuous
                                ),
                                border: .init(
                                    width: 0,
                                    color: Colors.transparent,
                                    opacity: 1
                                ),
                                shadow: .init(
                                    color: Colors.transparent,
                                    opacity: 1,
                                    radius: 0,
                                    xAxis: 0,
                                    yAxis: 0,
                                    isMirroring: false
                                ),
                                innerShadow: .init(
                                    color: Colors.transparent,
                                    opacity: 1,
                                    radius: 0,
                                    xAxis: 0,
                                    yAxis: 0,
                                    isMirroring: false
                                ),
                                alignment: .vertical(.center),
                                spacing: 8,
                                padding: .init(
                                    position: .none,
                                    amount: 0
                                ),
                                opacity: 1,
                                rotation: 0,
                                sublayers: [
                                    .init(
                                        id: "Item.41",
                                        name: "Item - 1",
                                        type: .shape(.roundedRectangle),
                                        frame: .init(
                                            width: 24,
                                            height: 10
                                        ),
                                        fill: .gradient,
                                        color: Colors.pink,
                                        gradientStart: Colors.pinkGradientStart,
                                        gradientEnd: Colors.pinkGradientEnd,
                                        fillOpacity: 1,
                                        corners: .init(
                                            radius: 5,
                                            type: .continuous
                                        ),
                                        border: .init(
                                            width: 0,
                                            color: Colors.transparent,
                                            opacity: 1
                                        ),
                                        shadow: .init(
                                            color: Colors.transparent,
                                            opacity: 1,
                                            radius: 0,
                                            xAxis: 0,
                                            yAxis: 0,
                                            isMirroring: false
                                        ),
                                        innerShadow: .init(
                                            color: Colors.pink,
                                            opacity: 0.64,
                                            radius: 2,
                                            xAxis: 2,
                                            yAxis: 2,
                                            isMirroring: true
                                        ),
                                        alignment: .generic(.center),
                                        spacing: 0,
                                        padding: .init(
                                            position: .none,
                                            amount: 0
                                        ),
                                        opacity: 1,
                                        rotation: 0,
                                        sublayers: nil
                                    ),
                                    .init(
                                        id: "Item.42",
                                        name: "Item - 2",
                                        type: .shape(.roundedRectangle),
                                        frame: .init(
                                            width: 48,
                                            height: 10
                                        ),
                                        fill: .gradient,
                                        color: Colors.green,
                                        gradientStart: Colors.greenGradientStart,
                                        gradientEnd: Colors.greenGradientEnd,
                                        fillOpacity: 1,
                                        corners: .init(
                                            radius: 5,
                                            type: .continuous
                                        ),
                                        border: .init(
                                            width: 0,
                                            color: Colors.transparent,
                                            opacity: 1
                                        ),
                                        shadow: .init(
                                            color: Colors.transparent,
                                            opacity: 1,
                                            radius: 0,
                                            xAxis: 0,
                                            yAxis: 0,
                                            isMirroring: false
                                        ),
                                        innerShadow: .init(
                                            color: Colors.green,
                                            opacity: 0.64,
                                            radius: 2,
                                            xAxis: 2,
                                            yAxis: 2,
                                            isMirroring: true
                                        ),
                                        alignment: .generic(.center),
                                        spacing: 0,
                                        padding: .init(
                                            position: .none,
                                            amount: 0
                                        ),
                                        opacity: 1,
                                        rotation: 0,
                                        sublayers: nil
                                    ),
                                    .init(
                                        id: "Item.43",
                                        name: "Item - 3",
                                        type: .shape(.roundedRectangle),
                                        frame: .init(
                                            width: 80,
                                            height: 10
                                        ),
                                        fill: .gradient,
                                        color: Colors.blue,
                                        gradientStart: Colors.blueGradientStart,
                                        gradientEnd: Colors.blueGradientEnd,
                                        fillOpacity: 1,
                                        corners: .init(
                                            radius: 5,
                                            type: .continuous
                                        ),
                                        border: .init(
                                            width: 0,
                                            color: Colors.transparent,
                                            opacity: 1
                                        ),
                                        shadow: .init(
                                            color: Colors.transparent,
                                            opacity: 1,
                                            radius: 0,
                                            xAxis: 0,
                                            yAxis: 0,
                                            isMirroring: false
                                        ),
                                        innerShadow: .init(
                                            color: Colors.blue,
                                            opacity: 0.64,
                                            radius: 2,
                                            xAxis: 2,
                                            yAxis: 2,
                                            isMirroring: true
                                        ),
                                        alignment: .generic(.center),
                                        spacing: 0,
                                        padding: .init(
                                            position: .none,
                                            amount: 0
                                        ),
                                        opacity: 1,
                                        
                                        rotation: 0,
                                        sublayers: nil
                                    )
                                ]
                            ),
                            .init(
                                id: "Item.44",
                                name: "Item - 13",
                                type: .stack(.horizontal),
                                frame: .init(
                                    width: nil,
                                    height: nil
                                ),
                                fill: .none,
                                color: Colors.transparent,
                                gradientStart: Colors.transparent,
                                gradientEnd: Colors.transparent,
                                fillOpacity: 1,
                                corners: .init(
                                    radius: 0,
                                    type: .continuous
                                ),
                                border: .init(
                                    width: 0,
                                    color: Colors.transparent,
                                    opacity: 1
                                ),
                                shadow: .init(
                                    color: Colors.transparent,
                                    opacity: 1,
                                    radius: 0,
                                    xAxis: 0,
                                    yAxis: 0,
                                    isMirroring: false
                                ),
                                innerShadow: .init(
                                    color: Colors.transparent,
                                    opacity: 1,
                                    radius: 0,
                                    xAxis: 0,
                                    yAxis: 0,
                                    isMirroring: false
                                ),
                                alignment: .vertical(.center),
                                spacing: 8,
                                padding: .init(
                                    position: .none,
                                    amount: 0
                                ),
                                opacity: 1,
                                rotation: 0,
                                sublayers: [
                                    .init(
                                        id: "Item.45",
                                        name: "Item - 1",
                                        type: .shape(.roundedRectangle),
                                        frame: .init(
                                            width: 160,
                                            height: 10
                                        ),
                                        fill: .gradient,
                                        color: Colors.orange,
                                        gradientStart: Colors.orangeGradientStart,
                                        gradientEnd: Colors.orangeGradientEnd,
                                        fillOpacity: 1,
                                        corners: .init(
                                            radius: 5,
                                            type: .continuous
                                        ),
                                        border: .init(
                                            width: 0,
                                            color: Colors.transparent,
                                            opacity: 1
                                        ),
                                        shadow: .init(
                                            color: Colors.transparent,
                                            opacity: 1,
                                            radius: 0,
                                            xAxis: 0,
                                            yAxis: 0,
                                            isMirroring: false
                                        ),
                                        innerShadow: .init(
                                            color: Colors.orange,
                                            opacity: 0.64,
                                            radius: 2,
                                            xAxis: 2,
                                            yAxis: 2,
                                            isMirroring: true
                                        ),
                                        alignment: .generic(.center),
                                        spacing: 0,
                                        padding: .init(
                                            position: .none,
                                            amount: 0
                                        ),
                                        opacity: 1,
                                        rotation: 0,
                                        sublayers: nil
                                    ),
                                    .init(
                                        id: "Item.46",
                                        name: "Item - 2",
                                        type: .shape(.roundedRectangle),
                                        frame: .init(
                                            width: 16,
                                            height: 10
                                        ),
                                        fill: .gradient,
                                        color: Colors.purple,
                                        gradientStart: Colors.purpleGradientStart,
                                        gradientEnd: Colors.purpleGradientEnd,
                                        fillOpacity: 1,
                                        corners: .init(
                                            radius: 5,
                                            type: .continuous
                                        ),
                                        border: .init(
                                            width: 0,
                                            color: Colors.transparent,
                                            opacity: 1
                                        ),
                                        shadow: .init(
                                            color: Colors.transparent,
                                            opacity: 1,
                                            radius: 0,
                                            xAxis: 0,
                                            yAxis: 0,
                                            isMirroring: false
                                        ),
                                        innerShadow: .init(
                                            color: Colors.purple,
                                            opacity: 0.64,
                                            radius: 2,
                                            xAxis: 2,
                                            yAxis: 2,
                                            isMirroring: true
                                        ),
                                        alignment: .generic(.center),
                                        spacing: 0,
                                        padding: .init(
                                            position: .none,
                                            amount: 0
                                        ),
                                        opacity: 1,
                                        rotation: 0,
                                        sublayers: nil
                                    )
                                ]
                            ),
                            .init(
                                id: "Item.47",
                                name: "Item - 14",
                                type: .stack(.horizontal),
                                frame: .init(
                                    width: nil,
                                    height: nil
                                ),
                                fill: .none,
                                color: Colors.transparent,
                                gradientStart: Colors.transparent,
                                gradientEnd: Colors.transparent,
                                fillOpacity: 1,
                                corners: .init(
                                    radius: 0,
                                    type: .continuous
                                ),
                                border: .init(
                                    width: 0,
                                    color: Colors.transparent,
                                    opacity: 1
                                ),
                                shadow: .init(
                                    color: Colors.transparent,
                                    opacity: 1,
                                    radius: 0,
                                    xAxis: 0,
                                    yAxis: 0,
                                    isMirroring: false
                                ),
                                innerShadow: .init(
                                    color: Colors.transparent,
                                    opacity: 1,
                                    radius: 0,
                                    xAxis: 0,
                                    yAxis: 0,
                                    isMirroring: false
                                ),
                                alignment: .vertical(.center),
                                spacing: 8,
                                padding: .init(
                                    position: .none,
                                    amount: 0
                                ),
                                opacity: 1,
                                rotation: 0,
                                sublayers: [
                                    .init(
                                        id: "Item.48",
                                        name: "Item - 1",
                                        type: .shape(.roundedRectangle),
                                        frame: .init(
                                            width: 64,
                                            height: 10
                                        ),
                                        fill: .gradient,
                                        color: Colors.pink,
                                        gradientStart: Colors.pinkGradientStart,
                                        gradientEnd: Colors.pinkGradientEnd,
                                        fillOpacity: 1,
                                        corners: .init(
                                            radius: 5,
                                            type: .continuous
                                        ),
                                        border: .init(
                                            width: 0,
                                            color: Colors.transparent,
                                            opacity: 1
                                        ),
                                        shadow: .init(
                                            color: Colors.transparent,
                                            opacity: 1,
                                            radius: 0,
                                            xAxis: 0,
                                            yAxis: 0,
                                            isMirroring: false
                                        ),
                                        innerShadow: .init(
                                            color: Colors.pink,
                                            opacity: 0.64,
                                            radius: 2,
                                            xAxis: 2,
                                            yAxis: 2,
                                            isMirroring: true
                                        ),
                                        alignment: .generic(.center),
                                        spacing: 0,
                                        padding: .init(
                                            position: .none,
                                            amount: 0
                                        ),
                                        opacity: 1,
                                        rotation: 0,
                                        sublayers: nil
                                    ),
                                    .init(
                                        id: "Item.49",
                                        name: "Item - 2",
                                        type: .shape(.roundedRectangle),
                                        frame: .init(
                                            width: 32,
                                            height: 10
                                        ),
                                        fill: .gradient,
                                        color: Colors.green,
                                        gradientStart: Colors.greenGradientStart,
                                        gradientEnd: Colors.greenGradientEnd,
                                        fillOpacity: 1,
                                        corners: .init(
                                            radius: 5,
                                            type: .continuous
                                        ),
                                        border: .init(
                                            width: 0,
                                            color: Colors.transparent,
                                            opacity: 1
                                        ),
                                        shadow: .init(
                                            color: Colors.transparent,
                                            opacity: 1,
                                            radius: 0,
                                            xAxis: 0,
                                            yAxis: 0,
                                            isMirroring: false
                                        ),
                                        innerShadow: .init(
                                            color: Colors.green,
                                            opacity: 0.64,
                                            radius: 2,
                                            xAxis: 2,
                                            yAxis: 2,
                                            isMirroring: true
                                        ),
                                        alignment: .generic(.center),
                                        spacing: 0,
                                        padding: .init(
                                            position: .none,
                                            amount: 0
                                        ),
                                        opacity: 1,
                                        rotation: 0,
                                        sublayers: nil
                                    )
                                ]
                            ),
                            .init(
                                id: "Item.50",
                                name: "Item - 15",
                                type: .shape(.roundedRectangle),
                                frame: .init(
                                    width: 184,
                                    height: 10
                                ),
                                fill: .gradient,
                                color: Colors.blue,
                                gradientStart: Colors.blueGradientStart,
                                gradientEnd: Colors.blueGradientEnd,
                                fillOpacity: 1,
                                corners: .init(
                                    radius: 5,
                                    type: .continuous
                                ),
                                border: .init(
                                    width: 0,
                                    color: Colors.transparent,
                                    opacity: 1
                                ),
                                shadow: .init(
                                    color: Colors.transparent,
                                    opacity: 1,
                                    radius: 0,
                                    xAxis: 0,
                                    yAxis: 0,
                                    isMirroring: false
                                ),
                                innerShadow: .init(
                                    color: Colors.blue,
                                    opacity: 0.64,
                                    radius: 2,
                                    xAxis: 2,
                                    yAxis: 2,
                                    isMirroring: true
                                ),
                                alignment: .generic(.center),
                                spacing: 0,
                                padding: .init(
                                    position: .none,
                                    amount: 0
                                ),
                                opacity: 1,
                                rotation: 0,
                                sublayers: nil
                            ),
                            .init(
                                id: "Item.51",
                                name: "Item - 16",
                                type: .stack(.horizontal),
                                frame: .init(
                                    width: nil,
                                    height: nil
                                ),
                                fill: .none,
                                color: Colors.transparent,
                                gradientStart: Colors.transparent,
                                gradientEnd: Colors.transparent,
                                fillOpacity: 1,
                                corners: .init(
                                    radius: 0,
                                    type: .continuous
                                ),
                                border: .init(
                                    width: 0,
                                    color: Colors.transparent,
                                    opacity: 1
                                ),
                                shadow: .init(
                                    color: Colors.transparent,
                                    opacity: 1,
                                    radius: 0,
                                    xAxis: 0,
                                    yAxis: 0,
                                    isMirroring: false
                                ),
                                innerShadow: .init(
                                    color: Colors.transparent,
                                    opacity: 1,
                                    radius: 0,
                                    xAxis: 0,
                                    yAxis: 0,
                                    isMirroring: false
                                ),
                                alignment: .vertical(.center),
                                spacing: 8,
                                padding: .init(
                                    position: .none,
                                    amount: 0
                                ),
                                opacity: 1,
                                rotation: 0,
                                sublayers: [
                                    .init(
                                        id: "Item.52",
                                        name: "Item - 1",
                                        type: .shape(.roundedRectangle),
                                        frame: .init(
                                            width: 48,
                                            height: 10
                                        ),
                                        fill: .gradient,
                                        color: Colors.orange,
                                        gradientStart: Colors.orangeGradientStart,
                                        gradientEnd: Colors.orangeGradientEnd,
                                        fillOpacity: 1,
                                        corners: .init(
                                            radius: 5,
                                            type: .continuous
                                        ),
                                        border: .init(
                                            width: 0,
                                            color: Colors.transparent,
                                            opacity: 1
                                        ),
                                        shadow: .init(
                                            color: Colors.transparent,
                                            opacity: 1,
                                            radius: 0,
                                            xAxis: 0,
                                            yAxis: 0,
                                            isMirroring: false
                                        ),
                                        innerShadow: .init(
                                            color: Colors.orange,
                                            opacity: 0.64,
                                            radius: 2,
                                            xAxis: 2,
                                            yAxis: 2,
                                            isMirroring: true
                                        ),
                                        alignment: .generic(.center),
                                        spacing: 0,
                                        padding: .init(
                                            position: .none,
                                            amount: 0
                                        ),
                                        opacity: 1,
                                        rotation: 0,
                                        sublayers: nil
                                    ),
                                    .init(
                                        id: "Item.53",
                                        name: "Item - 2",
                                        type: .shape(.roundedRectangle),
                                        frame: .init(
                                            width: 96,
                                            height: 10
                                        ),
                                        fill: .gradient,
                                        color: Colors.purple,
                                        gradientStart: Colors.purpleGradientStart,
                                        gradientEnd: Colors.purpleGradientEnd,
                                        fillOpacity: 1,
                                        corners: .init(
                                            radius: 5,
                                            type: .continuous
                                        ),
                                        border: .init(
                                            width: 0,
                                            color: Colors.transparent,
                                            opacity: 1
                                        ),
                                        shadow: .init(
                                            color: Colors.transparent,
                                            opacity: 1,
                                            radius: 0,
                                            xAxis: 0,
                                            yAxis: 0,
                                            isMirroring: false
                                        ),
                                        innerShadow: .init(
                                            color: Colors.purple,
                                            opacity: 0.64,
                                            radius: 2,
                                            xAxis: 2,
                                            yAxis: 2,
                                            isMirroring: true
                                        ),
                                        alignment: .generic(.center),
                                        spacing: 0,
                                        padding: .init(
                                            position: .none,
                                            amount: 0
                                        ),
                                        opacity: 1,
                                        rotation: 0,
                                        sublayers: nil
                                    ),
                                    .init(
                                        id: "Item.54",
                                        name: "Item - 3",
                                        type: .shape(.roundedRectangle),
                                        frame: .init(
                                            width: 64,
                                            height: 10
                                        ),
                                        fill: .gradient,
                                        color: Colors.pink,
                                        gradientStart: Colors.pinkGradientStart,
                                        gradientEnd: Colors.pinkGradientEnd,
                                        fillOpacity: 1,
                                        corners: .init(
                                            radius: 5,
                                            type: .continuous
                                        ),
                                        border: .init(
                                            width: 0,
                                            color: Colors.transparent,
                                            opacity: 1
                                        ),
                                        shadow: .init(
                                            color: Colors.transparent,
                                            opacity: 1,
                                            radius: 0,
                                            xAxis: 0,
                                            yAxis: 0,
                                            isMirroring: false
                                        ),
                                        innerShadow: .init(
                                            color: Colors.pink,
                                            opacity: 0.64,
                                            radius: 2,
                                            xAxis: 2,
                                            yAxis: 2,
                                            isMirroring: true
                                        ),
                                        alignment: .generic(.center),
                                        spacing: 0,
                                        padding: .init(
                                            position: .none,
                                            amount: 0
                                        ),
                                        opacity: 1,
                                        rotation: 0,
                                        sublayers: nil
                                    )
                                ]
                            )
                        ]
                    )
                ]
            )
        ]
    }
}
