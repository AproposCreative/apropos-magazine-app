//
//  SelectButtonLabelView.swift
//  Native
//

import SwiftUI

struct SelectButtonLabelView: View {
    
    // MARK: - Private properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
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
        isSelected: Bool
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
    }
    
    // MARK: - Private computed properties:
    
    /// Icon to display that is based on whether or not the value is selected:
    private var icon: String {
        isSelected ? selectedIcon : unselectedIcon
    }
    
    /// Symbol variant of the icon that is based on the selected state:
    private var iconSymbolVariant: SymbolVariants {
        isSelected ? selectedSymbolVariant : unselectedSymbolVariant
    }
    
    /// Font of the icon to display that is based on whether or not the value is selected:
    private var font: Font {
        isSelected ? selectedFont : unselectedFont
    }
    
    /// Color of the icon to display that is based on whether or not the value is selected:
    private var color: Color {
        isSelected ? selectedColor : unselectedColor
    }
    
    /// Starting color of the gradient of the icon to display that is based on whether or not the value is selected if applicable:
    private var gradientStart: Color {
        isSelected ? selectedGradientStart : unselectedGradientStart
    }
    
    /// Ending color of the gradient of the icon to display that is based on whether or not the value is selected if applicable:
    private var gradientEnd: Color {
        isSelected ? selectedGradientEnd : unselectedGradientEnd
    }
    
    /// 'Bool' value indicating whether or not the color of the icon to display should have a gradient applied to it that is based on whether or not the value is selected:
    private var isGradient: Bool {
        isSelected ? isSelectedGradient : isUnselectedGradient
    }
    
    /// Value of the frame of the view that is based on the size of the dynamic type that is currently selected:
    private var frameValue: CGFloat? {
        if let frame {
            switch dynamicTypeSize {
            case .xSmall: return frame * 0.7
            case .small: return frame * 0.8
            case .medium: return frame * 0.9
            case .large: return frame
            case .xLarge: return frame * 1.05
            case .xxLarge: return frame * 1.1
            case .xxxLarge: return frame * 1.15
            case .accessibility1: return frame * 1.2
            case .accessibility2: return frame * 1.4
            case .accessibility3: return frame * 1.6
            case .accessibility4: return frame * 1.8
            case .accessibility5: return frame * 2
            @unknown default: return frame
            }
        } else {
            return nil
        }
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        Image(systemName: icon)
            .symbolVariant(iconSymbolVariant)
            .font(font)
            .foregroundGradient(
                color: color,
                gradientStart: gradientStart,
                gradientEnd: gradientEnd,
                isGradient: isGradient
            )
            .frame(
                width: frameValue,
                height: frameValue,
                alignment: frameAlignment
            )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        SelectButtonLabelView(
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
            isSelected: true
        )
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
