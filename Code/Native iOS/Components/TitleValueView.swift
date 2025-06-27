//
//  TitleValueView.swift
//  Native
//

import SwiftUI

struct TitleValueView: View {
    
    // MARK: - Private properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
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
    
    /// Color of the title:
    private let titleColor: Color
    
    /// Starting color of the gradient of the title if applicable:
    private let titleGradientStart: Color
    
    /// Ending color of the gradient of the title if applicable:
    private let titleGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the title should have a gradient applied to it:
    private let isTitleColorGradient: Bool
    
    /// Maximum width of the title:
    private let titleMaxWidth: CGFloat?
    
    /// Alignment of the title if it has a maximum width applied to it:
    private let titleMaxWidthAlignment: Alignment
    
    /// An actual value to display if applicable:
    private let value: String
    
    /// 'Bool' value indicating whether or not the value should be localized if applicable:
    private let isValueLocalized: Bool
    
    /// Font of the value if applicable:
    private let valueFont: Font
    
    /// Text case of the value if applicable:
    private let valueTextCase: Text.Case?
    
    /// Alignment of the value if applicable:
    private let valueAlignment: TextAlignment
    
    /// Additional spacing between the multiple lines of the value if applicable:
    private let valueLineSpacing: Double
    
    /// Color of the value if applicable:
    private let valueColor: Color
    
    /// Starting color of the gradient of the value if applicable:
    private let valueGradientStart: Color
    
    /// Ending color of the gradient of the value if applicable:
    private let valueGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the value should have a gradient applied to it if applicable:
    private let isValueColorGradient: Bool
    
    /// Alignment of the content of the view:
    private let alignment: NT_Alignment
    
    /// Vertical alignment of the content of the view:
    private let verticalAlignment: VerticalAlignment
    
    /// Horizontal alignment of the content of the view:
    private let horizontalAlignment: HorizontalAlignment
    
    /// Spacing between the content of the view:
    private let spacing: Double
    
    /// Vertical padding around the content of the view:
    private let verticalPadding: Double
    
    /// Horizontal padding around the content of the view:
    private let horizontalPadding: Double
    
    /// Maximum height that the view can have if applicable:
    private let maxHeight: CGFloat?
    
    /// Alignment of the view if it has a maximum height applied to it:
    private let maxHeightAlignment: Alignment
    
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
    
    /// 'Bool' value indicating whether or not the divider at the top of the view should be shown at all:
    private let isShowingTopDivider: Bool
    
    /// Width that the divider that is displayed at the top of the view should have if applicable:
    private let topDividerWidth: CGFloat?
    
    /// Height that the divider that is displayed at the top of the view should have if applicable:
    private let topDividerHeight: CGFloat?
    
    /// Color of the divider that is displayed at the top of the view:
    private let topDividerColor: Color
    
    /// Radius of the rounded corners of the divider that is displayed at the top of the view:
    private let topDividerCornerRadius: Double
    
    /// Style of the rounded corners of the divider that is displayed at the top of the view:
    private let topDividerCornerStyle: RoundedCornerStyle
    
    /// 'Bool' value indicating whether or not the divider at the bottom of the view should be shown at all:
    private let isShowingBottomDivider: Bool
    
    /// Width that the divider that is displayed at the bottom of the view should have if applicable:
    private let bottomDividerWidth: CGFloat?
    
    /// Height that the divider that is displayed at the bottom of the view should have if applicable:
    private let bottomDividerHeight: CGFloat?
    
    /// Color of the divider that is displayed at the bottom of the view:
    private let bottomDividerColor: Color
    
    /// Radius of the rounded corners of the divider that is displayed at the bottom of the view:
    private let bottomDividerCornerRadius: Double
    
    /// Style of the rounded corners of the divider that is displayed at the bottom of the view:
    private let bottomDividerCornerStyle: RoundedCornerStyle
    
    /// Alignment of the content of the view and the dividers if applicable:
    private let dividersAlignment: HorizontalAlignment
    
    /// Spacing between the content of the view and the dividers if applicable:
    private let dividersSpacing: Double
    
    init(
        title: String,
        isTitleLocalized: Bool = true,
        titleFont: Font = .body,
        titleTextCase: Text.Case? = .none,
        titleAlignment: TextAlignment = .leading,
        titleLineSpacing: Double = 0,
        titleColor: Color = .secondary,
        titleGradientStart: Color = .blueGradientStart,
        titleGradientEnd: Color = .blueGradientEnd,
        isTitleColorGradient: Bool = false,
        titleMaxWidth: CGFloat? = .infinity,
        titleMaxWidthAlignment: Alignment = .leading,
        value: String,
        isValueLocalized: Bool = true,
        valueFont: Font = .headline,
        valueTextCase: Text.Case? = .none,
        valueAlignment: TextAlignment = .trailing,
        valueLineSpacing: Double = 0,
        valueColor: Color = .primary,
        valueGradientStart: Color = .blueGradientStart,
        valueGradientEnd: Color = .blueGradientEnd,
        isValueColorGradient: Bool = false,
        alignment: NT_Alignment = .horizontal,
        verticalAlignment: VerticalAlignment = .top,
        horizontalAlignment: HorizontalAlignment = .leading,
        spacing: Double = 12,
        verticalPadding: Double = 0,
        horizontalPadding: Double = 0,
        maxHeight: CGFloat? = nil,
        maxHeightAlignment: Alignment = .topLeading,
        isShowingBackground: Bool = false,
        backgroundColor: Color = .init(.systemGroupedBackground),
        backgroundGradientStart: Color = .blueGradientStart,
        backgroundGradientEnd: Color = .blueGradientEnd,
        isBackgroundColorGradient: Bool = false,
        cornerRadius: Double = 0,
        cornerStyle: RoundedCornerStyle = .continuous,
        isShowingTopDivider: Bool = false,
        topDividerWidth: CGFloat? = nil,
        topDividerHeight: CGFloat? = 1,
        topDividerColor: Color = .init(.systemFill),
        topDividerCornerRadius: Double = 0.5,
        topDividerCornerStyle: RoundedCornerStyle = .continuous,
        isShowingBottomDivider: Bool = true,
        bottomDividerWidth: CGFloat? = nil,
        bottomDividerHeight: CGFloat? = 1,
        bottomDividerColor: Color = .init(.systemFill),
        bottomDividerCornerRadius: Double = 0.5,
        bottomDividerCornerStyle: RoundedCornerStyle = .continuous,
        dividersAlignment: HorizontalAlignment = .leading,
        dividersSpacing: Double = 12
    ) {
        
        /// Properties initialization:
        self.title = title
        self.isTitleLocalized = isTitleLocalized
        self.titleFont = titleFont
        self.titleTextCase = titleTextCase
        self.titleAlignment = titleAlignment
        self.titleLineSpacing = titleLineSpacing
        self.titleColor = titleColor
        self.titleGradientStart = titleGradientStart
        self.titleGradientEnd = titleGradientEnd
        self.isTitleColorGradient = isTitleColorGradient
        self.titleMaxWidth = titleMaxWidth
        self.titleMaxWidthAlignment = titleMaxWidthAlignment
        self.value = value
        self.isValueLocalized = isValueLocalized
        self.valueFont = valueFont
        self.valueTextCase = valueTextCase
        self.valueAlignment = valueAlignment
        self.valueLineSpacing = valueLineSpacing
        self.valueColor = valueColor
        self.valueGradientStart = valueGradientStart
        self.valueGradientEnd = valueGradientEnd
        self.isValueColorGradient = isValueColorGradient
        self.alignment = alignment
        self.verticalAlignment = verticalAlignment
        self.horizontalAlignment = horizontalAlignment
        self.spacing = spacing
        self.verticalPadding = verticalPadding
        self.horizontalPadding = horizontalPadding
        self.maxHeight = maxHeight
        self.maxHeightAlignment = maxHeightAlignment
        self.isShowingBackground = isShowingBackground
        self.backgroundColor = backgroundColor
        self.backgroundGradientStart = backgroundGradientStart
        self.backgroundGradientEnd = backgroundGradientEnd
        self.isBackgroundColorGradient = isBackgroundColorGradient
        self.cornerRadius = cornerRadius
        self.cornerStyle = cornerStyle
        self.isShowingTopDivider = isShowingTopDivider
        self.topDividerWidth = topDividerWidth
        self.topDividerHeight = topDividerHeight
        self.topDividerColor = topDividerColor
        self.topDividerCornerRadius = topDividerCornerRadius
        self.topDividerCornerStyle = topDividerCornerStyle
        self.isShowingBottomDivider = isShowingBottomDivider
        self.bottomDividerWidth = bottomDividerWidth
        self.bottomDividerHeight = bottomDividerHeight
        self.bottomDividerColor = bottomDividerColor
        self.bottomDividerCornerRadius = bottomDividerCornerRadius
        self.bottomDividerCornerStyle = bottomDividerCornerStyle
        self.dividersAlignment = dividersAlignment
        self.dividersSpacing = dividersSpacing
    }
    
    // MARK: - Private computed properties:
    
    /// Value of the alignment of the view that is based on the size of the dynamic type that is currently selected:
    private var alignmentValue: NT_Alignment {
        dynamicTypeSize >= .accessibility1 ? .vertical : alignment
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .accessibilityElement(children: .combine)
    }
}

// MARK: - Item:

private extension TitleValueView {
    private var item: some View {
        VStack(
            alignment: dividersAlignment,
            spacing: dividersSpacing
        ) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        topDivider
        titleValue
        bottomDivider
    }
}

// MARK: - Dividers:

private extension TitleValueView {
    private var topDivider: some View {
        DividerView(
            isShowing: isShowingTopDivider,
            width: topDividerWidth,
            height: topDividerHeight,
            color: topDividerColor,
            cornerRadius: topDividerCornerRadius,
            cornerStyle: topDividerCornerStyle
        )
    }
    
    private var bottomDivider: some View {
        DividerView(
            isShowing: isShowingBottomDivider,
            width: bottomDividerWidth,
            height: bottomDividerHeight,
            color: bottomDividerColor,
            cornerRadius: bottomDividerCornerRadius,
            cornerStyle: bottomDividerCornerStyle
        )
    }
}

// MARK: - Title and value:

private extension TitleValueView {
    private var titleValue: some View {
        titleValueContent
            .contentBackground(
                verticalPadding: verticalPadding,
                horizontalPadding: horizontalPadding,
                maxHeight: maxHeight,
                maxHeightAlignment: maxHeightAlignment,
                isShowingBackground: isShowingBackground,
                backgroundColor: backgroundColor,
                backgroundGradientStart: backgroundGradientStart,
                backgroundGradientEnd: backgroundGradientEnd,
                isBackgroundColorGradient: isBackgroundColorGradient,
                cornerRadius: cornerRadius,
                cornerStyle: cornerStyle
            )
    }
    
    @ViewBuilder
    private var titleValueContent: some View {
        switch alignmentValue {
        case .horizontal: horizontalTitleValueItem
        case .vertical: verticalTitleValueItem
        }
    }
    
    private var horizontalTitleValueItem: some View {
        HStack(
            alignment: verticalAlignment,
            spacing: spacing
        ) {
            titleValueItem
        }
    }
    
    private var verticalTitleValueItem: some View {
        VStack(
            alignment: horizontalAlignment,
            spacing: spacing
        ) {
            titleValueItem
        }
    }
    
    @ViewBuilder
    private var titleValueItem: some View {
        titleContent
        valueContent
    }
}

// MARK: - Title:

private extension TitleValueView {
    private var titleContent: some View {
        titleItem
            .font(titleFont)
            .textCase(titleTextCase)
            .multilineTextAlignment(titleAlignment)
            .lineSpacing(titleLineSpacing)
            .foregroundGradient(
                color: titleColor,
                gradientStart: titleGradientStart,
                gradientEnd: titleGradientEnd,
                isGradient: isTitleColorGradient
            )
            .frame(
                maxWidth: titleMaxWidth,
                alignment: titleMaxWidthAlignment
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

// MARK: - Value:

private extension TitleValueView {
    private var valueContent: some View {
        valueItem
            .font(valueFont)
            .textCase(valueTextCase)
            .multilineTextAlignment(valueAlignment)
            .lineSpacing(valueLineSpacing)
            .foregroundGradient(
                color: valueColor,
                gradientStart: valueGradientStart,
                gradientEnd: valueGradientEnd,
                isGradient: isValueColorGradient
            )
    }
    
    @ViewBuilder
    private var valueItem: some View {
        if isValueLocalized {
            Text(.init(value))
        } else {
            Text(value)
        }
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        TitleValueView(
            title: "Title",
            isTitleLocalized: true,
            titleFont: .body,
            titleTextCase: .none,
            titleAlignment: .leading,
            titleLineSpacing: 0,
            titleColor: .secondary,
            titleGradientStart: .blueGradientStart,
            titleGradientEnd: .blueGradientEnd,
            isTitleColorGradient: false,
            titleMaxWidth: .infinity,
            titleMaxWidthAlignment: .leading,
            value: "Value",
            isValueLocalized: true,
            valueFont: .headline,
            valueTextCase: .none,
            valueAlignment: .trailing,
            valueLineSpacing: 0,
            valueColor: .primary,
            valueGradientStart: .blueGradientStart,
            valueGradientEnd: .blueGradientEnd,
            isValueColorGradient: false,
            alignment: .horizontal,
            verticalAlignment: .top,
            horizontalAlignment: .leading,
            spacing: 12,
            verticalPadding: 0,
            horizontalPadding: 0,
            maxHeight: nil,
            maxHeightAlignment: .topLeading,
            isShowingBackground: false,
            backgroundColor: .init(.systemGroupedBackground),
            backgroundGradientStart: .blueGradientStart,
            backgroundGradientEnd: .blueGradientEnd,
            isBackgroundColorGradient: false,
            cornerRadius: 0,
            cornerStyle: .continuous,
            isShowingTopDivider: false,
            topDividerWidth: nil,
            topDividerHeight: 1,
            topDividerColor: .init(.systemFill),
            topDividerCornerRadius: 0.5,
            topDividerCornerStyle: .continuous,
            isShowingBottomDivider: true,
            bottomDividerWidth: nil,
            bottomDividerHeight: 1,
            bottomDividerColor: .init(.systemFill),
            bottomDividerCornerRadius: 0.5,
            bottomDividerCornerStyle: .continuous,
            dividersAlignment: .leading,
            dividersSpacing: 12
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
}
