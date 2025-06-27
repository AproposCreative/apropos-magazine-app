//
//  ColorPickerView.swift
//  Native
//

import SwiftUI

struct ColorPickerView: View {
    
    // MARK: - Private properties:
    
    /// Color that is currently selected:
    @Binding private var selectedColor: NT_Color?
    
    /// An array of the colors to select from:
    private let colors: [NT_Color]
    
    /// Size of the frame of each of the colors that aren't selected:
    private let colorFrame: Double
    
    /// Size of the frame of the color that is currently selected:
    private let selectedColorFrame: Double
    
    /// Radius of the rounded corners of each of the colors that aren't selected:
    private let colorCornerRadius: Double
    
    /// Radius of the rounded corners of the color that is currently selected:
    private let selectedColorCornerRadius: Double
    
    /// Style of the rounded corners of each of the colors:
    private let colorCornerStyle: RoundedCornerStyle
    
    /// Width of the border of the color that is currently selected:
    private let selectedColorBorderWidth: Double
    
    /// Spacing between the content of the view:
    private let spacing: Double
    
    /// Vertical padding around the content of the view:
    private let verticalPadding: Double
    
    /// Horizontal padding around the content of the view:
    private let horizontalPadding: Double
    
    /// 'Bool' value indicating whether or not the background of the view should be shown at all:
    private let isShowingBackground: Bool
    
    /// Color of the background of the view:
    private let backgroundColor: Color
    
    /// Starting color of the gradient of the background of the view if applicable:
    private let backgroundGradientStart: Color
    
    /// Ending color of the gradient of the background of the view if applicable:
    private let backgroundGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the background of the view should have a gradient applied to it:
    private let isBackgroundColorGradient: Bool
    
    /// Radius of the rounded corners of the view:
    private let cornerRadius: Double
    
    /// Style of the rounded corners of the view:
    private let cornerStyle: RoundedCornerStyle
    
    /// 'Bool' value indicating whether or not the haptic feedback should be triggered after selecting the color:
    private let isSelectionHapticFeedbackEnabled: Bool
    
    init(
        selectedColor: Binding<NT_Color?>,
        colors: [NT_Color],
        colorFrame: Double = 48,
        selectedColorFrame: Double = 56,
        colorCornerRadius: Double = 12,
        selectedColorCornerRadius: Double = 16,
        colorCornerStyle: RoundedCornerStyle = .continuous,
        selectedColorBorderWidth: Double = 2,
        spacing: Double = 8,
        verticalPadding: Double = 12,
        horizontalPadding: Double = 12,
        isShowingBackground: Bool = true,
        backgroundColor: Color = .init(.secondarySystemGroupedBackground),
        backgroundGradientStart: Color = .blueGradientStart,
        backgroundGradientEnd: Color = .blueGradientEnd,
        isBackgroundColorGradient: Bool = false,
        cornerRadius: Double = 16,
        cornerStyle: RoundedCornerStyle = .continuous,
        isSelectionHapticFeedbackEnabled: Bool = true
    ) {
        
        /// Properties initialization:
        _selectedColor = selectedColor
        self.colors = colors
        self.colorFrame = colorFrame
        self.selectedColorFrame = selectedColorFrame
        self.colorCornerRadius = colorCornerRadius
        self.selectedColorCornerRadius = selectedColorCornerRadius
        self.colorCornerStyle = colorCornerStyle
        self.selectedColorBorderWidth = selectedColorBorderWidth
        self.isSelectionHapticFeedbackEnabled = isSelectionHapticFeedbackEnabled
        self.spacing = spacing
        self.verticalPadding = verticalPadding
        self.horizontalPadding = horizontalPadding
        self.isShowingBackground = isShowingBackground
        self.backgroundColor = backgroundColor
        self.backgroundGradientStart = backgroundGradientStart
        self.backgroundGradientEnd = backgroundGradientEnd
        self.isBackgroundColorGradient = isBackgroundColorGradient
        self.cornerRadius = cornerRadius
        self.cornerStyle = cornerStyle
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be shown at all:
    private var isShowing: Bool {
        !colors.isEmpty
    }
    
    /// An array of the grid items to display the colors:
    private var gridItems: [GridItem] {
        [
            .init(
                .adaptive(minimum: selectedColorFrame),
                spacing: spacing,
                alignment: .center
            )
        ]
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    @ViewBuilder
    private var content: some View {
        if isShowing {
            mainContent
        }
    }
    
    private var mainContent: some View {
        item
            .contentBackground(
                verticalPadding: verticalPadding,
                horizontalPadding: horizontalPadding,
                isShowingBackground: isShowingBackground,
                backgroundColor: backgroundColor,
                backgroundGradientStart: backgroundGradientStart,
                backgroundGradientEnd: backgroundGradientEnd,
                isBackgroundColorGradient: isBackgroundColorGradient,
                cornerRadius: cornerRadius,
                cornerStyle: cornerStyle
            )
            .animation(
                .default,
                value: selectedColor
            )
    }
}

// MARK: - Item:

private extension ColorPickerView {
    private var item: some View {
        LazyVGrid(
            columns: gridItems,
            spacing: spacing
        ) {
            colorsContent
        }
    }
}

// MARK: - Colors:

private extension ColorPickerView {
    private var colorsContent: some View {
        ForEach(
            colors,
            content: color
        )
    }
    
    private func color(_ color: NT_Color) -> some View {
        colorContent(color)
            .frame(
                width: selectedColorFrame,
                height: selectedColorFrame,
                alignment: .center
            )
            .onTapGesture {
                select(color)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title(color))
            .accessibilityAddTraits(accessibilityTraits(color))
    }
    
    private func colorContent(_ color: NT_Color) -> some View {
        ZStack {
            colorItem(color)
        }
    }
    
    @ViewBuilder
    private func colorItem(_ color: NT_Color) -> some View {
        selected(color)
        colorItemContent(color)
    }
    
    private func colorItemContent(_ color: NT_Color) -> some View {
        Rectangle()
            .gradientFill(
                color: colorValue(color),
                gradientStart: gradientStart(color),
                gradientEnd: gradientEnd(color),
                isGradient: isGradient(color)
            )
            .frame(
                width: colorFrame,
                height: colorFrame,
                alignment: .center
            )
            .roundedCorners(
                cornerRadius: colorCornerRadius,
                cornerStyle: colorCornerStyle
            )
    }
}

// MARK: - Selected:

private extension ColorPickerView {
    @ViewBuilder
    private func selected(_ color: NT_Color) -> some View {
        if isSelected(color),
           let selectedColor {
            selectedContent(selectedColor)
        }
    }
    
    private func selectedContent(_ color: NT_Color) -> some View {
        Rectangle()
            .fill(.clear)
            .contentBackground(
                verticalPadding: 0,
                horizontalPadding: 0,
                isShowingBackground: false,
                cornerRadius: selectedColorCornerRadius,
                cornerStyle: colorCornerStyle,
                borderWidth: selectedColorBorderWidth,
                borderColor: colorValue(color),
                borderGradientStart: gradientStart(color),
                borderGradientEnd: gradientEnd(color),
                isBorderGradient: isGradient(color)
            )
    }
}

// MARK: - Functions:

private extension ColorPickerView {
    
    // MARK: - Private functions:
    
    /// Returns a 'Bool' value indicating whether or not the given color is currently selected:
    private func isSelected(_ color: NT_Color) -> Bool {
        selectedColor == color
    }
    
    /// Returns the title of the given color:
    private func title(_ color: NT_Color) -> String {
        color.title
    }
    
    /// Returns the value of the color of the given color:
    private func colorValue(_ color: NT_Color) -> Color {
        color.color
    }
    
    /// Returns the starting color of the gradient of the given color:
    private func gradientStart(_ color: NT_Color) -> Color {
        color.gradientStart
    }
    
    /// Returns the ending color of the gradient of the given color:
    private func gradientEnd(_ color: NT_Color) -> Color {
        color.gradientEnd
    }
    
    /// Returns a 'Bool' value indicating whether or not the color of the given color should have a gradient applied to it:
    private func isGradient(_ color: NT_Color) -> Bool {
        color.isGradient
    }
    
    /// Returns the accessibility traits of the given color that is based on whether or not it's currently selected:
    private func accessibilityTraits(_ color: NT_Color) -> AccessibilityTraits {
        isSelected(color) ? [
            .isButton,
            .isSelected
        ] : .isButton
    }
    
    /// Selects the given color unless it's already selected:
    private func select(_ color: NT_Color) {
        
        /// Firstly making sure that the given color isn't already selected:
        if !isSelected(color) {
            
            /// If yes, then selecting the given the color by updating the 'selectedColor' property with the given color:
            selectedColor = color
            
            /// Lastly triggering the selection changed haptic feedback indicating that there was a change if needed:
            HapticFeedbacks.selectionChanged(isEnabled: isSelectionHapticFeedbackEnabled)
        }
    }
}

// MARK: - Preview:

#Preview {
    @Previewable @State var selectedColor: NT_Color? = .example.first
    
    ScrollView {
        ColorPickerView(
            selectedColor: $selectedColor,
            colors: NT_Color.example,
            colorFrame: 48,
            selectedColorFrame: 56,
            colorCornerRadius: 12,
            selectedColorCornerRadius: 16,
            colorCornerStyle: .continuous,
            selectedColorBorderWidth: 2,
            spacing: 8,
            verticalPadding: 12,
            horizontalPadding: 12,
            isShowingBackground: true,
            backgroundColor: .init(.secondarySystemGroupedBackground),
            backgroundGradientStart: .blueGradientStart,
            backgroundGradientEnd: .blueGradientEnd,
            isBackgroundColorGradient: false,
            cornerRadius: 16,
            cornerStyle: .continuous,
            isSelectionHapticFeedbackEnabled: true
        )
    }
    .safeAreaPadding(
        .all,
        16
    )
    .safeAreaPadding(
        .bottom,
        16
    )
    .background(Color(.systemGroupedBackground))
}
