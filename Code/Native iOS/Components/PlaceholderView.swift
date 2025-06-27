//
//  PlaceholderView.swift
//  Native
//

import SwiftUI

struct PlaceholderView: View {
    
    // MARK: - Private properties:
    
    /// An actual title to display:
    private let title: String
    
    /// 'Bool' value indicating whether or not the title should be localized:
    private let isTitleLocalized: Bool
    
    /// Font of the title:
    private let titleFont: Font
    
    /// Text case of the title:
    private let titleTextCase: Text.Case?
    
    /// Alignment of the title:
    private let titleAlignment: TextAlignment
    
    /// Additional spacing between the multiple lines of the title:
    private let titleLineSpacing: Double
    
    /// Maximum number of lines that the title can have if applicable:
    private let titleLineLimit: Int?
    
    /// Color of the title:
    private let titleColor: Color?
    
    /// Starting color of the gradient of the title if applicable:
    private let titleGradientStart: Color
    
    /// Ending color of the gradient of the title if applicable:
    private let titleGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the title should have a gradient applied to it:
    private let isTitleColorGradient: Bool
    
    /// Vertical padding around the content of the view:
    private let verticalPadding: Double
    
    /// Horizontal padding around the content of the view:
    private let horizontalPadding: Double
    
    init(
        title: String,
        isTitleLocalized: Bool = true,
        titleFont: Font = .body,
        titleTextCase: Text.Case? = .none,
        titleAlignment: TextAlignment = .center,
        titleLineSpacing: Double = 0,
        titleLineLimit: Int? = nil,
        titleColor: Color? = .secondary,
        titleGradientStart: Color = .blueGradientStart,
        titleGradientEnd: Color = .blueGradientEnd,
        isTitleColorGradient: Bool = false,
        verticalPadding: Double = 16,
        horizontalPadding: Double = 16
    ) {
        
        /// Properties initialization:
        self.title = title
        self.isTitleLocalized = isTitleLocalized
        self.titleFont = titleFont
        self.titleTextCase = titleTextCase
        self.titleAlignment = titleAlignment
        self.titleLineSpacing = titleLineSpacing
        self.titleLineLimit = titleLineLimit
        self.titleColor = titleColor
        self.titleGradientStart = titleGradientStart
        self.titleGradientEnd = titleGradientEnd
        self.isTitleColorGradient = isTitleColorGradient
        self.verticalPadding = verticalPadding
        self.horizontalPadding = horizontalPadding
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        titleContent
            .padding(
                .vertical,
                verticalPadding
            )
            .padding(
                .horizontal,
                horizontalPadding
            )
    }
}

// MARK: - Title:

private extension PlaceholderView {
    private var titleContent: some View {
        titleItem
            .font(titleFont)
            .textCase(titleTextCase)
            .multilineTextAlignment(titleAlignment)
            .lineSpacing(titleLineSpacing)
            .lineLimit(titleLineLimit)
            .foregroundGradient(
                color: titleColor,
                gradientStart: titleGradientStart,
                gradientEnd: titleGradientEnd,
                isGradient: isTitleColorGradient
            )
    }
    
    @ViewBuilder
    private var titleItem: some View {
        if isTitleLocalized {
            Text(.init(title))
        } else {
            Text(title)
        }
    }
}

// MARK: - Preview:

#Preview {
    PlaceholderView(
        title: "Title",
        isTitleLocalized: true,
        titleFont: .body,
        titleTextCase: .none,
        titleAlignment: .center,
        titleLineSpacing: 0,
        titleLineLimit: nil,
        titleColor: .secondary,
        titleGradientStart: .blueGradientStart,
        titleGradientEnd: .blueGradientEnd,
        isTitleColorGradient: false,
        verticalPadding: 16,
        horizontalPadding: 16
    )
}
