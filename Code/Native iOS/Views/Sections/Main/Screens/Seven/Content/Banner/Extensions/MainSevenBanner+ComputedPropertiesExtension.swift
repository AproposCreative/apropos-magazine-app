//
//  MainSevenBanner+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension MainSevenBannerView {
    
    // MARK: - Computed properties:
    
    /// An array of the buttons to display in the banner:
    var buttons: [NT_Button] {
        [
            .init(
                id: "Explore.Products",
                title: "Explore Products",
                isTitleLocalized: true,
                titleFont: .subheadline.bold(),
                titleTextCase: .none,
                titleAlignment: .center,
                titleColor: .accent,
                titleGradientStart: .blueGradientStart,
                titleGradientEnd: .blueGradientEnd,
                isTitleColorGradient: false,
                icon: Icons.mailStack,
                iconSymbolVariant: .fill,
                iconFont: .subheadline.bold(),
                iconColor: .accent,
                iconGradientStart: .blueGradientStart,
                iconGradientEnd: .blueGradientEnd,
                isIconColorGradient: false,
                style: .titleOnly,
                isLoading: false,
                loadingIndicatorColor: .accent,
                loadingIndicatorScale: 1,
                loadingIndicatorFrame: nil,
                verticalPadding: 8,
                horizontalPadding: 8,
                isFullWidth: true,
                alignment: .center,
                isShowingBackground: true,
                backgroundColor: primaryColor,
                backgroundGradientStart: .blueGradientStart,
                backgroundGradientEnd: .blueGradientEnd,
                isBackgroundColorGradient: false,
                cornerRadius: 10,
                cornerStyle: .continuous,
                role: nil,
                isDisabled: false,
                keyboardShortcut: nil,
                action: showProducts
            )
        ]
    }
    
    /// Primary color of the view:
    var primaryColor: Color {
        .white
    }
    
    /// Secondary color of the view:
    var secondaryColor: Color {
        primaryColor.opacity(0.8)
    }
    
    /// Tertiary color of the view:
    var tertiaryColor: Color {
        primaryColor.opacity(0.6)
    }
    
    /// Size of the frame of the 'Dismiss' button that is based on the size of the dynamic type that is currently selected:
    var dismissFrame: CGFloat? {
        dynamicTypeSize >= .accessibility1 ? nil : 24
    }
}
