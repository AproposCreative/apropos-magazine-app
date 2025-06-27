//
//  EmptyStateView.swift
//  Native
//

import SwiftUI

struct EmptyStateView: View {
    
    // MARK: - Private properties:
    
    /// An actual icon to display:
    private let icon: String
    
    /// An actual title to display:
    private let title: String
    
    /// An actual subtitle to display:
    private let subtitle: String
    
    init(
        icon: String = Icons.tray,
        title: String = "Nothing Selected",
        subtitle: String = "Please select something to view it here."
    ) {
        
        /// Properties initialization:
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        IconBackgroundTitleSubtitleView(
            icon: icon,
            iconSize: .sixtyFourPixels,
            title: title,
            titleFont: .title2.bold(),
            titleAlignment: .center,
            subtitle: subtitle,
            subtitleFont: .body,
            subtitleAlignment: .center,
            titleSubtitleAlignment: .center,
            titleSubtitleSpacing: 12,
            titleSubtitleMaxWidthAlignment: .center,
            alignment: .vertical,
            horizontalAlignment: .center,
            spacing: 24,
            verticalPadding: 16,
            horizontalPadding: 16,
            isShowingBackground: false,
            cornerRadius: 0
        )
    }
}

// MARK: - Preview:

#Preview {
    EmptyStateView(
        icon: Icons.tray,
        title: "Nothing Selected",
        subtitle: "Please select something to view it here."
    )
}
