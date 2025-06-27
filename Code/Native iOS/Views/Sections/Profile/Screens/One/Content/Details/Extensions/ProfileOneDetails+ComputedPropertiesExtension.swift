//
//  ProfileOneDetails+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension ProfileOneDetailsView {
    
    // MARK: - Computed properties:
    
    /// An array of the stats to display:
    var stats: [NT_ProfileTaskStat] {
        NT_ProfileTaskStat.example.dropLast()
    }
    
    /// An array of the columns to display the stats in the grid:
    var columns: [GridItem] {
        [
            .init(
                .adaptive(
                    minimum: gridItemMinWidth,
                    maximum: gridItemMaxWidth
                ),
                spacing: spacing,
                alignment: .topLeading
            )
        ]
    }
    
    /// An array of the buttons to display in the banner:
    var bannerButtons: [NT_Button] {
        [
            .init(
                id: "Explore.Button",
                title: "Explore",
                isTitleLocalized: true,
                titleFont: .subheadline.bold(),
                titleTextCase: .none,
                titleAlignment: .center,
                titleColor: .primary,
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
                loadingIndicatorColor: .secondary,
                loadingIndicatorScale: 1,
                loadingIndicatorFrame: nil,
                verticalPadding: 8,
                horizontalPadding: 8,
                isFullWidth: true,
                alignment: .center,
                isShowingBackground: true,
                backgroundColor: .init(.systemGroupedBackground),
                backgroundGradientStart: .blueGradientStart,
                backgroundGradientEnd: .blueGradientEnd,
                isBackgroundColorGradient: false,
                cornerRadius: 10,
                cornerStyle: .continuous,
                role: nil,
                isDisabled: false,
                keyboardShortcut: nil,
                action: showLatestBlogPost
            )
        ]
    }
    
    /// Image of the user to display:
    var image: Image {
        .init(.profile1)
    }
    
    /// Spacing between the content of the view:
    var spacing: Double {
        16
    }
    
    /// Padding around the content of each of the stats:
    var statPadding: Double {
        12
    }
    
    /// Size of the frame of the 'Dismiss' button that is based on the size of the dynamic type that is currently selected:
    var dismissFrame: CGFloat? {
        shouldMoveContent ? nil : 24
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be moved that is based on the size of the dynamic type that is currently selected:
    private var shouldMoveContent: Bool {
        dynamicTypeSize >= .accessibility1
    }
    
    /// Minimum width that each of the grid items should have that is based on the size of the dynamic type that is currently selected:
    private var gridItemMinWidth: Double {
        shouldMoveContent ? 200 : 96
    }
    
    /// Maximum width that each of the grid items can have that is based on the size of the dynamic type that is currently selected:
    private var gridItemMaxWidth: Double {
        shouldMoveContent ? 400 : 144
    }
}
