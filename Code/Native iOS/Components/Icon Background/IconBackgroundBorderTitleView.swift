//
//  IconBackgroundBorderTitleView.swift
//  Native
//

import SwiftUI

struct IconBackgroundBorderTitleView: View {
    
    // MARK: - Private properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    /// An actual icon to display:
    private let icon: String
    
    /// Symbol variant of the icon (It could be '.fill', '.circle', etc.):
    private let iconSymbolVariant: SymbolVariants
    
    /// Color of the icon:
    private let iconColor: Color
    
    /// Starting color of the gradient of the icon if applicable:
    private let iconGradientStart: Color
    
    /// Ending color of the gradient of the icon if applicable:
    private let iconGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the icon should have a gradient applied to it:
    private let isIconColorGradient: Bool
    
    /// 'Bool' value indicating whether or not the background of the icon should be shown at all:
    private let isShowingIconBackground: Bool
    
    /// 'Bool' value indicating whether or not the icon should take the full width:
    private let isIconFullWidth: Bool
    
    /// Color of the background of the icon:
    private let iconBackgroundColor: Color
    
    /// Starting color of the gradient of the background of the icon if applicable:
    private let iconBackgroundGradientStart: Color
    
    /// Ending color of the gradient of the background of the icon if applicable:
    private let iconBackgroundGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the background color of the icon should have a gradient applied to it:
    private let isIconBackgroundColorGradient: Bool
    
    /// 'Bool' value indicating whether or not the background of the icon should have a circular shape:
    private let isIconCircularBackground: Bool
    
    /// Size of the icon:
    private let iconSize: NT_IconSize
    
    /// Width of the border of the icon if applicable:
    private let iconBorderWidth: Double
    
    /// Color of the border of the icon if applicable:
    private let iconBorderColor: Color
    
    /// Starting color of the gradient of the border of the icon if applicable:
    private let iconBorderGradientStart: Color
    
    /// Ending color of the gradient of the border of the icon if applicable:
    private let iconBorderGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the border of the icon should have a gradient applied to it:
    private let isIconBorderColorGradient: Bool
    
    /// Size of the frame of the border of the icon if applicable:
    private let iconBorderFrame: Double
    
    /// Radius of the rounded corners of the border of the icon if applicable:
    private let iconBorderCornerRadius: Double
    
    /// Style of the rounded corners of the border of the icon if applicable:
    private let iconBorderCornerStyle: RoundedCornerStyle
    
    /// 'Bool' value indicating whether or not the title should be shown at all:
    private let isShowingTitle: Bool
    
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
    
    /// 'Bool' value indicating whether or not the content of the view should be placed in reverse meaning that the title would be displayed first and the icon last:
    private let isReversed: Bool
    
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
    
    /// Action of the icon after single tapping on it if applicable:
    private let iconSingleTapAction: (() -> ())?
    
    /// Action of the icon after double tapping on it if applicable:
    private let iconDoubleTapAction: (() -> ())?
    
    init(
        icon: String,
        iconSymbolVariant: SymbolVariants = .fill,
        iconColor: Color = .accent,
        iconGradientStart: Color = .blueGradientStart,
        iconGradientEnd: Color = .blueGradientEnd,
        isIconColorGradient: Bool = true,
        isShowingIconBackground: Bool = true,
        isIconFullWidth: Bool = false,
        iconBackgroundColor: Color = .accent,
        iconBackgroundGradientStart: Color = .blueGradientStart.opacity(0.08),
        iconBackgroundGradientEnd: Color = .blueGradientEnd.opacity(0.08),
        isIconBackgroundColorGradient: Bool = true,
        isIconCircularBackground: Bool = true,
        iconSize: NT_IconSize = .fiftySixPixels,
        iconBorderWidth: Double = 2,
        iconBorderColor: Color = .init(.secondarySystemGroupedBackground),
        iconBorderGradientStart: Color = .blueGradientStart,
        iconBorderGradientEnd: Color = .blueGradientEnd,
        isIconBorderColorGradient: Bool = true,
        iconBorderFrame: Double = 64,
        iconBorderCornerRadius: Double = 32,
        iconBorderCornerStyle: RoundedCornerStyle = .continuous,
        isShowingTitle: Bool = true,
        title: String,
        isTitleLocalized: Bool = true,
        titleFont: Font = .caption2.bold(),
        titleTextCase: Text.Case? = .none,
        titleAlignment: TextAlignment = .center,
        titleLineSpacing: Double = 0,
        titleColor: Color = .primary,
        titleGradientStart: Color = .blueGradientStart,
        titleGradientEnd: Color = .blueGradientEnd,
        isTitleColorGradient: Bool = false,
        isReversed: Bool = false,
        alignment: NT_Alignment = .vertical,
        verticalAlignment: VerticalAlignment = .top,
        horizontalAlignment: HorizontalAlignment = .center,
        spacing: Double = 6,
        verticalPadding: Double = 0,
        horizontalPadding: Double = 0,
        maxHeight: CGFloat? = nil,
        maxHeightAlignment: Alignment = .topLeading,
        isShowingBackground: Bool = false,
        backgroundColor: Color = .init(.secondarySystemGroupedBackground),
        backgroundGradientStart: Color = .blueGradientStart,
        backgroundGradientEnd: Color = .blueGradientEnd,
        isBackgroundColorGradient: Bool = false,
        cornerRadius: Double = 0,
        cornerStyle: RoundedCornerStyle = .continuous,
        iconSingleTapAction: (() -> ())? = nil,
        iconDoubleTapAction: (() -> ())? = nil
    ) {
        
        /// Properties initialization:
        self.icon = icon
        self.iconSymbolVariant = iconSymbolVariant
        self.iconColor = iconColor
        self.iconGradientStart = iconGradientStart
        self.iconGradientEnd = iconGradientEnd
        self.isIconColorGradient = isIconColorGradient
        self.isShowingIconBackground = isShowingIconBackground
        self.isIconFullWidth = isIconFullWidth
        self.iconBackgroundColor = iconBackgroundColor
        self.iconBackgroundGradientStart = iconBackgroundGradientStart
        self.iconBackgroundGradientEnd = iconBackgroundGradientEnd
        self.isIconBackgroundColorGradient = isIconBackgroundColorGradient
        self.isIconCircularBackground = isIconCircularBackground
        self.iconSize = iconSize
        self.iconBorderWidth = iconBorderWidth
        self.iconBorderColor = iconBorderColor
        self.iconBorderGradientStart = iconBorderGradientStart
        self.iconBorderGradientEnd = iconBorderGradientEnd
        self.isIconBorderColorGradient = isIconBorderColorGradient
        self.iconBorderFrame = iconBorderFrame
        self.iconBorderCornerRadius = iconBorderCornerRadius
        self.iconBorderCornerStyle = iconBorderCornerStyle
        self.isShowingTitle = isShowingTitle
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
        self.isReversed = isReversed
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
        self.iconSingleTapAction = iconSingleTapAction
        self.iconDoubleTapAction = iconDoubleTapAction
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the border of the icon should be shown at all:
    private var isShowingIconBorder: Bool {
        iconBorderWidth > 0
    }
    
    /// Gradient of the border of the icon if applicable:
    private var iconBorderGradient: LinearGradient {
        .init(
            colors: [
                iconBorderGradientStart,
                iconBorderGradientEnd
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
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
            .accessibilityElement(children: .combine)
    }
}

// MARK: - Item:

private extension IconBackgroundBorderTitleView {
    @ViewBuilder
    private var item: some View {
        switch alignmentValue {
        case .horizontal: horizontalItem
        case .vertical: verticalItem
        }
    }
    
    private var horizontalItem: some View {
        HStack(
            alignment: verticalAlignment,
            spacing: spacing
        ) {
            itemContent
        }
    }
    
    private var verticalItem: some View {
        VStack(
            alignment: horizontalAlignment,
            spacing: spacing
        ) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        if isReversed {
            reversedItemContent
        } else {
            defaultItemContent
        }
    }
    
    @ViewBuilder
    private var reversedItemContent: some View {
        titleContent
        iconContent
    }
    
    @ViewBuilder
    private var defaultItemContent: some View {
        iconContent
        titleContent
    }
}

// MARK: - Icon:

private extension IconBackgroundBorderTitleView {
    private var iconContent: some View {
        ZStack {
            iconItem
        }
    }
    
    @ViewBuilder
    private var iconItem: some View {
        iconItemContent
        border
    }
    
    private var iconItemContent: some View {
        IconBackgroundView(
            icon: icon,
            symbolVariant: iconSymbolVariant,
            color: iconColor,
            gradientStart: iconGradientStart,
            gradientEnd: iconGradientEnd,
            isColorGradient: isIconColorGradient,
            isShowingBackground: isShowingIconBackground,
            isFullWidth: isIconFullWidth,
            backgroundColor: iconBackgroundColor,
            backgroundGradientStart: iconBackgroundGradientStart,
            backgroundGradientEnd: iconBackgroundGradientEnd,
            isBackgroundColorGradient: isIconBackgroundColorGradient,
            isCircularBackground: isIconCircularBackground,
            size: iconSize,
            singleTapAction: iconSingleTapAction,
            doubleTapAction: iconDoubleTapAction
        )
    }
    
    @ViewBuilder
    private var border: some View {
        if isShowingIconBorder {
            borderContent
        }
    }
    
    private var borderContent: some View {
        borderItem
            .frame(
                width: iconBorderFrame,
                height: iconBorderFrame,
                alignment: .center
            )
    }
    
    @ViewBuilder
    private var borderItem: some View {
        if isIconBorderColorGradient {
            gradientBorderItemContent
        } else {
            borderItemContent
        }
    }
    
    private var gradientBorderItemContent: some View {
        RoundedRectangle(
            cornerRadius: iconBorderCornerRadius,
            style: iconBorderCornerStyle
        )
        .stroke(
            iconBorderGradient,
            lineWidth: iconBorderWidth
        )
    }
    
    private var borderItemContent: some View {
        RoundedRectangle(
            cornerRadius: iconBorderCornerRadius,
            style: iconBorderCornerStyle
        )
        .stroke(
            iconBorderColor,
            lineWidth: iconBorderWidth
        )
    }
}

// MARK: - Title:

private extension IconBackgroundBorderTitleView {
    @ViewBuilder
    private var titleContent: some View {
        if isShowingTitle {
            titleItem
        }
    }
    
    private var titleItem: some View {
        titleItemContent
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
    }
    
    @ViewBuilder
    private var titleItemContent: some View {
        if isTitleLocalized {
            Text(.init(title))
        } else {
            Text(title)
        }
    }
}

// MARK: - Preview:

#Preview {
    IconBackgroundBorderTitleView(
        icon: Icons.plusCircle,
        iconSymbolVariant: .fill,
        iconColor: .accent,
        iconGradientStart: .blueGradientStart,
        iconGradientEnd: .blueGradientEnd,
        isIconColorGradient: true,
        isShowingIconBackground: true,
        isIconFullWidth: false,
        iconBackgroundColor: .accent,
        iconBackgroundGradientStart: .blueGradientStart.opacity(0.08),
        iconBackgroundGradientEnd: .blueGradientEnd.opacity(0.08),
        isIconBackgroundColorGradient: true,
        isIconCircularBackground: true,
        iconSize: .fiftySixPixels,
        iconBorderWidth: 2,
        iconBorderColor: .init(.secondarySystemGroupedBackground),
        iconBorderGradientStart: .blueGradientStart,
        iconBorderGradientEnd: .blueGradientEnd,
        isIconBorderColorGradient: true,
        iconBorderFrame: 64,
        iconBorderCornerRadius: 32,
        iconBorderCornerStyle: .continuous,
        title: "Title",
        isTitleLocalized: true,
        titleFont: .caption2.bold(),
        titleTextCase: .none,
        titleAlignment: .center,
        titleLineSpacing: 0,
        titleColor: .primary,
        titleGradientStart: .blueGradientStart,
        titleGradientEnd: .blueGradientEnd,
        isTitleColorGradient: false,
        isReversed: false,
        alignment: .vertical,
        verticalAlignment: .top,
        horizontalAlignment: .center,
        spacing: 6,
        verticalPadding: 0,
        horizontalPadding: 0,
        maxHeight: nil,
        maxHeightAlignment: .topLeading,
        isShowingBackground: false,
        backgroundColor: .init(.secondarySystemGroupedBackground),
        backgroundGradientStart: .blueGradientStart,
        backgroundGradientEnd: .blueGradientEnd,
        isBackgroundColorGradient: false,
        cornerRadius: 0,
        cornerStyle: .continuous
    ) {
        
    } iconDoubleTapAction: {
        
    }
    .padding()
}
