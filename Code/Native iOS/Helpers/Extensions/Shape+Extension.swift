//
//  Shape+Extension.swift
//  Native
//

import SwiftUI

extension Shape {
    
    // MARK: - Functions:
    
    /// Returns the shape with the gradient fill that is based on the given colors:
    @ViewBuilder
    func gradientFill(
        color: Color,
        gradientStart: Color,
        gradientEnd: Color,
        isGradient: Bool
    ) -> some View {
        if isGradient {
            self
                .fill(
                    LinearGradient(
                        colors: [
                            gradientStart,
                            gradientEnd
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        } else {
            self
                .fill(color)
        }
    }
    
    /// Returns the shape with the gradient border that is based on the given width and the colors:
    @ViewBuilder
    func gradientBorder(
        width: Double,
        color: Color,
        gradientStart: Color,
        gradientEnd: Color,
        isGradient: Bool
    ) -> some View {
        if isGradient {
            self
                .stroke(
                    LinearGradient(
                        colors: [
                            gradientStart,
                            gradientEnd
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: width
                )
        } else {
            self
                .stroke(
                    color,
                    lineWidth: width
                )
        }
    }
    
    /// Returns the view with the filled shape:
    @ViewBuilder
    func gradientShadowFill(
        color: Color,
        gradientStart: Color,
        gradientEnd: Color,
        isGradient: Bool,
        shadowColor: Color,
        shadowRadius: Double,
        shadowXAxis: Double,
        shadowYAxis: Double,
        isMirroringShadow: Bool,
        innerShadowColor: Color,
        innerShadowRadius: Double,
        innerShadowXAxis: Double,
        innerShadowYAxis: Double,
        isMirroringInnerShadow: Bool
    ) -> some View {
        if isGradient {
            if isMirroringShadow,
               isMirroringInnerShadow {
                self
                    .fill(
                        LinearGradient(
                            colors: [
                                gradientStart,
                                gradientEnd
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .shadow(
                            .inner(
                                color: innerShadowColor,
                                radius: innerShadowRadius,
                                x: innerShadowXAxis,
                                y: innerShadowYAxis
                            )
                        )
                        .shadow(
                            .inner(
                                color: innerShadowColor,
                                radius: innerShadowRadius,
                                x: -innerShadowXAxis,
                                y: -innerShadowYAxis
                            )
                        )
                        .shadow(
                            .drop(
                                color: shadowColor,
                                radius: shadowRadius,
                                x: shadowXAxis,
                                y: shadowYAxis
                            )
                        )
                        .shadow(
                            .drop(
                                color: shadowColor,
                                radius: shadowRadius,
                                x: -shadowXAxis,
                                y: -shadowYAxis
                            )
                        )
                    )
            } else if isMirroringShadow {
                self
                    .fill(
                        LinearGradient(
                            colors: [
                                gradientStart,
                                gradientEnd
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .shadow(
                            .inner(
                                color: innerShadowColor,
                                radius: innerShadowRadius,
                                x: innerShadowXAxis,
                                y: innerShadowYAxis
                            )
                        )
                        .shadow(
                            .drop(
                                color: shadowColor,
                                radius: shadowRadius,
                                x: shadowXAxis,
                                y: shadowYAxis
                            )
                        )
                        .shadow(
                            .drop(
                                color: shadowColor,
                                radius: shadowRadius,
                                x: -shadowXAxis,
                                y: -shadowYAxis
                            )
                        )
                    )
            } else if isMirroringInnerShadow {
                self
                    .fill(
                        LinearGradient(
                            colors: [
                                gradientStart,
                                gradientEnd
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .shadow(
                            .inner(
                                color: innerShadowColor,
                                radius: innerShadowRadius,
                                x: innerShadowXAxis,
                                y: innerShadowYAxis
                            )
                        )
                        .shadow(
                            .inner(
                                color: innerShadowColor,
                                radius: innerShadowRadius,
                                x: -innerShadowXAxis,
                                y: -innerShadowYAxis
                            )
                        )
                        .shadow(
                            .drop(
                                color: shadowColor,
                                radius: shadowRadius,
                                x: shadowXAxis,
                                y: shadowYAxis
                            )
                        )
                    )
            } else {
                self
                    .fill(
                        LinearGradient(
                            colors: [
                                gradientStart,
                                gradientEnd
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .shadow(
                            .inner(
                                color: innerShadowColor,
                                radius: innerShadowRadius,
                                x: innerShadowXAxis,
                                y: innerShadowYAxis
                            )
                        )
                        .shadow(
                            .drop(
                                color: shadowColor,
                                radius: shadowRadius,
                                x: shadowXAxis,
                                y: shadowYAxis
                            )
                        )
                    )
            }
        } else {
            if isMirroringShadow,
               isMirroringInnerShadow {
                self
                    .fill(
                        color
                            .shadow(
                                .inner(
                                    color: innerShadowColor,
                                    radius: innerShadowRadius,
                                    x: innerShadowXAxis,
                                    y: innerShadowYAxis
                                )
                            )
                            .shadow(
                                .inner(
                                    color: innerShadowColor,
                                    radius: innerShadowRadius,
                                    x: -innerShadowXAxis,
                                    y: -innerShadowYAxis
                                )
                            )
                            .shadow(
                                .drop(
                                    color: shadowColor,
                                    radius: shadowRadius,
                                    x: shadowXAxis,
                                    y: shadowYAxis
                                )
                            )
                            .shadow(
                                .drop(
                                    color: shadowColor,
                                    radius: shadowRadius,
                                    x: -shadowXAxis,
                                    y: -shadowYAxis
                                )
                            )
                    )
            } else if isMirroringShadow {
                self
                    .fill(
                        color
                            .shadow(
                                .inner(
                                    color: innerShadowColor,
                                    radius: innerShadowRadius,
                                    x: innerShadowXAxis,
                                    y: innerShadowYAxis
                                )
                            )
                            .shadow(
                                .drop(
                                    color: shadowColor,
                                    radius: shadowRadius,
                                    x: shadowXAxis,
                                    y: shadowYAxis
                                )
                            )
                            .shadow(
                                .drop(
                                    color: shadowColor,
                                    radius: shadowRadius,
                                    x: -shadowXAxis,
                                    y: -shadowYAxis
                                )
                            )
                    )
            } else if isMirroringInnerShadow {
                self
                    .fill(
                        color
                            .shadow(
                                .inner(
                                    color: innerShadowColor,
                                    radius: innerShadowRadius,
                                    x: innerShadowXAxis,
                                    y: innerShadowYAxis
                                )
                            )
                            .shadow(
                                .inner(
                                    color: innerShadowColor,
                                    radius: innerShadowRadius,
                                    x: -innerShadowXAxis,
                                    y: -innerShadowYAxis
                                )
                            )
                            .shadow(
                                .drop(
                                    color: shadowColor,
                                    radius: shadowRadius,
                                    x: shadowXAxis,
                                    y: shadowYAxis
                                )
                            )
                    )
            } else {
                self
                    .fill(
                        color
                            .shadow(
                                .inner(
                                    color: innerShadowColor,
                                    radius: innerShadowRadius,
                                    x: innerShadowXAxis,
                                    y: innerShadowYAxis
                                )
                            )
                            .shadow(
                                .drop(
                                    color: shadowColor,
                                    radius: shadowRadius,
                                    x: shadowXAxis,
                                    y: shadowYAxis
                                )
                            )
                    )
            }
        }
    }
}
