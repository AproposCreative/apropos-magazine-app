//
//  SelectButtonView.swift
//  Native
//

import SwiftUI

struct SelectButtonView: View {
    
    // MARK: - Private properties:
    
    /// Icon to display when the value is selected:
    private let selectedIcon: String
    
    /// Symbol variant of the icon to display when the value is selected:
    private let selectedSymbolVariant: SymbolVariants
    
    /// Font of the icon to display when the value is selected:
    private let selectedFont: Font
    
    /// Color of the icon to display when the value is selected:
    private let selectedColor: Color
    
    /// Starting color of the gradient of the icon to display when the value is selected if applicable:
    private let selectedGradientStart: Color
    
    /// Ending color of the gradient of the icon to display when the value is selected if applicable:
    private let selectedGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the icon to display when the value is selected should have a gradient applied to it:
    private let isSelectedGradient: Bool
    
    /// Icon to display when the value is not selected:
    private let unselectedIcon: String
    
    /// Symbol variant of the icon to display when the value is not selected:
    private let unselectedSymbolVariant: SymbolVariants
    
    /// Font of the icon to display when the value is not selected:
    private let unselectedFont: Font
    
    /// Color of the icon to display when the value is not selected:
    private let unselectedColor: Color
    
    /// Starting color of the gradient of the icon to display when the value is not selected if applicable:
    private let unselectedGradientStart: Color
    
    /// Ending color of the gradient of the icon to display when the value is not selected if applicable:
    private let unselectedGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the icon to display when the value is not selected should have a gradient applied to it:
    private let isUnselectedGradient: Bool
    
    /// Size of the frame of the button:
    private let frame: CGFloat?
    
    /// Alignment of the frame of the button:
    private let frameAlignment: Alignment
    
    /// 'Bool' value indicating whether or not the value is selected:
    private let isSelected: Bool
    
    /// 'Bool' value indicating whether or not the button should be shown at all:
    private let isShowing: Bool
    
    /// 'Bool' value indicating whether or not the button should be disabled:
    private let isDisabled: Bool
    
    /// An actual action to select if applicable:
    private let action: (() -> ())?
    
    init(
        selectedIcon: String = Icons.checkmarkCircle,
        selectedSymbolVariant: SymbolVariants = .fill,
        selectedFont: Font = .title2.weight(.semibold),
        selectedColor: Color = .accent,
        selectedGradientStart: Color = .blueGradientStart,
        selectedGradientEnd: Color = .blueGradientEnd,
        isSelectedGradient: Bool = true,
        unselectedIcon: String = Icons.circle,
        unselectedSymbolVariant: SymbolVariants = .none,
        unselectedFont: Font = .title2,
        unselectedColor: Color = .accent,
        unselectedGradientStart: Color = .blueGradientStart,
        unselectedGradientEnd: Color = .blueGradientEnd,
        isUnselectedGradient: Bool = true,
        frame: CGFloat? = 32,
        frameAlignment: Alignment = .center,
        isSelected: Bool,
        isShowing: Bool = true,
        isDisabled: Bool = false,
        action: (() -> ())? = nil
    ) {
        
        /// Properties initialization:
        self.selectedIcon = selectedIcon
        self.selectedSymbolVariant = selectedSymbolVariant
        self.selectedFont = selectedFont
        self.selectedColor = selectedColor
        self.selectedGradientStart = selectedGradientStart
        self.selectedGradientEnd = selectedGradientEnd
        self.isSelectedGradient = isSelectedGradient
        self.unselectedIcon = unselectedIcon
        self.unselectedSymbolVariant = unselectedSymbolVariant
        self.unselectedFont = unselectedFont
        self.unselectedColor = unselectedColor
        self.unselectedGradientStart = unselectedGradientStart
        self.unselectedGradientEnd = unselectedGradientEnd
        self.isUnselectedGradient = isUnselectedGradient
        self.frame = frame
        self.frameAlignment = frameAlignment
        self.isSelected = isSelected
        self.isShowing = isShowing
        self.isDisabled = isDisabled
        self.action = action
    }
    
    // MARK: - Private computed properties:
    
    /// Accessibility label of the button that is based on whether or not it's currently selected:
    private var accessibilityLabel: LocalizedStringKey {
        isSelected ? "Deselect" : "Select"
    }
    
    /// Accessibility traits of the button to indicate that it's an actual button, as well as whether or not it's currently selected:
    private var accessibilityTraits: AccessibilityTraits {
        isSelected ? [.isButton, .isSelected] : .isButton
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    @ViewBuilder
    private var content: some View {
        if isShowing {
            item
        }
    }
}

// MARK: - Item:

private extension SelectButtonView {
    private var item: some View {
        itemContent
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(accessibilityTraits)
    }
    
    private var itemContent: some View {
        Button {
            action?()
        } label: {
            label
        }
    }
}

// MARK: - Label:

private extension SelectButtonView {
    private var label: some View {
        SelectButtonLabelView(
            selectedIcon: selectedIcon,
            selectedSymbolVariant: selectedSymbolVariant,
            selectedFont: selectedFont,
            selectedColor: selectedColor,
            selectedGradientStart: selectedGradientStart,
            selectedGradientEnd: selectedGradientEnd,
            isSelectedGradient: isSelectedGradient,
            unselectedIcon: unselectedIcon,
            unselectedSymbolVariant: unselectedSymbolVariant,
            unselectedFont: unselectedFont,
            unselectedColor: unselectedColor,
            unselectedGradientStart: unselectedGradientStart,
            unselectedGradientEnd: unselectedGradientEnd,
            isUnselectedGradient: isUnselectedGradient,
            frame: frame,
            frameAlignment: frameAlignment,
            isSelected: isSelected
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        SelectButtonView(
            selectedIcon: Icons.checkmarkCircle,
            selectedSymbolVariant: .fill,
            selectedFont: .title2.weight(.semibold),
            selectedColor: .blue,
            selectedGradientStart: .blue,
            selectedGradientEnd: .indigo,
            isSelectedGradient: true,
            unselectedIcon: Icons.circle,
            unselectedSymbolVariant: .none,
            unselectedFont: .title2,
            unselectedColor: .blue,
            unselectedGradientStart: .blue,
            unselectedGradientEnd: .indigo,
            isUnselectedGradient: true,
            frame: 32,
            frameAlignment: .center,
            isSelected: true,
            isShowing: true,
            isDisabled: false
        ) {
            
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .contentBackground()
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
