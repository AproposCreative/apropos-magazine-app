//
//  NT_Link.swift
//  Native
//

import SwiftUI

struct NT_Link {
    
    // MARK: - Properties:
    
    /// Identifier of the link:
    let id: String
    
    /// 'Bool' value indicating whether or not the title of the link should be shown at all:
    let isShowingTitle: Bool
    
    /// Title of the link to display:
    let title: String
    
    /// 'Bool' value indicating whether or not the title of the link should be localized:
    let isTitleLocalized: Bool
    
    /// 'Bool' value indicating whether or not the subtitle of the link should be shown at all:
    let isShowingSubtitle: Bool
    
    /// Subtitle of the link to display:
    let subtitle: String
    
    /// 'Bool' value indicating whether or not the subtitle of the link should be localized:
    let isSubtitleLocalized: Bool
    
    /// 'Bool' value indicating whether or not the icon of the link should be shown at all:
    let isShowingIcon: Bool
    
    /// Icon of the link to display if needed:
    let icon: String
    
    /// Color of the link:
    let color: Color
    
    /// Starting color of the gradient of the link if applicable:
    let gradientStart: Color
    
    /// Ending color of the gradient of the link if applicable:
    let gradientEnd: Color
    
    /// An actual URL of the link:
    let url: URL
    
    init(
        id: String,
        isShowingTitle: Bool,
        title: String,
        isTitleLocalized: Bool,
        isShowingSubtitle: Bool,
        subtitle: String,
        isSubtitleLocalized: Bool,
        isShowingIcon: Bool,
        icon: String,
        color: Color,
        gradientStart: Color,
        gradientEnd: Color,
        url: URL
    ) {
        
        /// Properties initialization:
        self.id = id
        self.isShowingTitle = isShowingTitle
        self.title = title
        self.isTitleLocalized = isTitleLocalized
        self.isShowingSubtitle = isShowingSubtitle
        self.subtitle = subtitle
        self.isSubtitleLocalized = isSubtitleLocalized
        self.isShowingIcon = isShowingIcon
        self.icon = icon
        self.color = color
        self.gradientStart = gradientStart
        self.gradientEnd = gradientEnd
        self.url = url
    }
}

// MARK: - Identifiable:

extension NT_Link: Identifiable {  }

// MARK: - Equatable:

extension NT_Link: Equatable {  }

// MARK: - Hashable:

extension NT_Link: Hashable {  }

// MARK: - Example:

extension NT_Link {
    
    // MARK: - Computed properties:
    
    /// An array of the example links:
    static var example: [NT_Link] {
        [
            .init(
                id: "Terms.Of.Service",
                isShowingTitle: true,
                title: "Terms of Service",
                isTitleLocalized: true,
                isShowingSubtitle: false,
                subtitle: "",
                isSubtitleLocalized: false,
                isShowingIcon: false,
                icon: Icons.docText,
                color: .accent,
                gradientStart: .blueGradientStart,
                gradientEnd: .blueGradientEnd,
                url: Links.termsOfService
            ),
            .init(
                id: "Privacy.Policy",
                isShowingTitle: true,
                title: "Privacy Policy",
                isTitleLocalized: true,
                isShowingSubtitle: false,
                subtitle: "",
                isSubtitleLocalized: false,
                isShowingIcon: false,
                icon: Icons.docText,
                color: .accent,
                gradientStart: .blueGradientStart,
                gradientEnd: .blueGradientEnd,
                url: Links.privacyPolicy
            )
        ]
    }
}
