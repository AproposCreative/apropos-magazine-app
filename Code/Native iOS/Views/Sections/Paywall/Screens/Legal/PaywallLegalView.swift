//
//  PaywallLegalView.swift
//  Native
//

import SwiftUI

struct PaywallLegalView: View {
    
    // MARK: - Private properties:
    
    /// Color of the view:
    private let color: Color
    
    /// Color of the divider:
    private let dividerColor: Color
    
    init(
        color: Color = .secondary,
        dividerColor: Color = .init(.systemFill)
    ) {
        
        /// Properties initialization:
        self.color = color
        self.dividerColor = dividerColor
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        LinksView(
            links: links,
            titleFont: .footnote,
            titleAlignment: .center,
            titleColor: color,
            titleSubtitleAlignment: .center,
            titleSubtitleMaxWidthAlignment: .center,
            isShowingLinkBackground: false,
            linkCornerRadius: 0,
            isShowingDivider: true,
            dividerColor: dividerColor,
            alignment: .horizontal,
            verticalAlignment: .center,
            spacing: 12
        )
    }
}

// MARK: - Preview:

#Preview {
    PaywallLegalView(
        color: .secondary,
        dividerColor: .init(.systemFill)
    )
    .padding()
}
