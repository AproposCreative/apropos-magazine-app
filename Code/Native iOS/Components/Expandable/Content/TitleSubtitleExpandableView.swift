//
//  TitleSubtitleExpandableView.swift
//  Native
//

import SwiftUI

struct TitleSubtitleExpandableView: View {
    
    // MARK: - Private properties:
    
    /// 'Bool' value indicating whether or not the content should be expanded:
    @State private var isExpanded: Bool = false
    
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
    private let titleColor: Color?
    
    /// An actual subtitle to display:
    private let subtitle: String
    
    /// 'Bool' value indicating whether or not the subtitle should be localized:
    private let isSubtitleLocalized: Bool
    
    /// Font of the subtitle:
    private let subtitleFont: Font
    
    /// Text case of the subtitle:
    private let subtitleTextCase: Text.Case?
    
    /// Alignment of the subtitle:
    private let subtitleAlignment: TextAlignment
    
    /// Additional spacing between the multiple lines of the subtitle:
    private let subtitleLineSpacing: Double
    
    /// Color of the subtitle:
    private let subtitleColor: Color?
    
    /// Icon of the 'Expand' button:
    private let expandButtonIcon: String
    
    /// Symbol variant of the 'Expand' button (It could be '.fill', '.circle', etc.):
    private let expandButtonSymbolVariant: SymbolVariants
    
    /// Color of the 'Expand' button:
    private let expandButtonColor: Color
    
    /// Starting color of the gradient of the 'Expand' button if applicable:
    private let expandButtonGradientStart: Color
    
    /// Ending color of the gradient of the 'Expand' button if applicable:
    private let expandButtonGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the 'Expand' button should have a gradient applied to it:
    private let isExpandButtonColorGradient: Bool
    
    /// Size of the icon of the 'Expand' button:
    private let expandButtonIconSize: NT_IconSize
    
    /// Alignment of the title and the 'Expand' button:
    private let titleExpandButtonAlignment: VerticalAlignment
    
    /// Spacing between the title and the 'Expand' button:
    private let titleExpandButtonSpacing: Double
    
    /// Alignment of the content of the view:
    private let alignment: HorizontalAlignment
    
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
    
    /// 'Bool' value indicating whether or not the haptic feedback should be triggered after expanding or collapsing the subtitle:
    private let isExpandHapticFeedbackEnabled: Bool
    
    init(
        isExpanded: Bool = false,
        title: String,
        isTitleLocalized: Bool = true,
        titleFont: Font = .headline,
        titleTextCase: Text.Case? = .none,
        titleAlignment: TextAlignment = .leading,
        titleLineSpacing: Double = 0,
        titleColor: Color? = .primary,
        subtitle: String,
        isSubtitleLocalized: Bool = true,
        subtitleFont: Font = .subheadline,
        subtitleTextCase: Text.Case? = .none,
        subtitleAlignment: TextAlignment = .leading,
        subtitleLineSpacing: Double = 0,
        subtitleColor: Color? = .secondary,
        expandButtonIcon: String = Icons.chevronRight,
        expandButtonSymbolVariant: SymbolVariants = .fill,
        expandButtonColor: Color = .accent,
        expandButtonGradientStart: Color = .blueGradientStart,
        expandButtonGradientEnd: Color = .blueGradientEnd,
        isExpandButtonColorGradient: Bool = true,
        expandButtonIconSize: NT_IconSize = .custom(
            font: .headline,
            nonBackgroundFont: .headline,
            frame: 22,
            cornerRadius: 0,
            cornerStyle: .continuous
        ),
        titleExpandButtonAlignment: VerticalAlignment = .top,
        titleExpandButtonSpacing: Double = 12,
        alignment: HorizontalAlignment = .leading,
        spacing: Double = 4,
        verticalPadding: Double = 12,
        horizontalPadding: Double = 12,
        maxHeight: CGFloat? = nil,
        maxHeightAlignment: Alignment = .topLeading,
        isShowingBackground: Bool = true,
        backgroundColor: Color = .init(.secondarySystemGroupedBackground),
        backgroundGradientStart: Color = .blueGradientStart,
        backgroundGradientEnd: Color = .blueGradientEnd,
        isBackgroundColorGradient: Bool = false,
        cornerRadius: Double = 16,
        cornerStyle: RoundedCornerStyle = .continuous,
        isExpandHapticFeedbackEnabled: Bool = true
    ) {
        
        /// Properties initialization:
        _isExpanded = State(initialValue: isExpanded)
        self.title = title
        self.isTitleLocalized = isTitleLocalized
        self.titleFont = titleFont
        self.titleTextCase = titleTextCase
        self.titleAlignment = titleAlignment
        self.titleLineSpacing = titleLineSpacing
        self.titleColor = titleColor
        self.subtitle = subtitle
        self.isSubtitleLocalized = isSubtitleLocalized
        self.subtitleFont = subtitleFont
        self.subtitleTextCase = subtitleTextCase
        self.subtitleAlignment = subtitleAlignment
        self.subtitleLineSpacing = subtitleLineSpacing
        self.subtitleColor = subtitleColor
        self.expandButtonIcon = expandButtonIcon
        self.expandButtonSymbolVariant = expandButtonSymbolVariant
        self.expandButtonColor = expandButtonColor
        self.expandButtonGradientStart = expandButtonGradientStart
        self.expandButtonGradientEnd = expandButtonGradientEnd
        self.isExpandButtonColorGradient = isExpandButtonColorGradient
        self.expandButtonIconSize = expandButtonIconSize
        self.titleExpandButtonAlignment = titleExpandButtonAlignment
        self.titleExpandButtonSpacing = titleExpandButtonSpacing
        self.alignment = alignment
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
        self.isExpandHapticFeedbackEnabled = isExpandHapticFeedbackEnabled
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
    }
}

// MARK: - Item:

private extension TitleSubtitleExpandableView {
    private var item: some View {
        VStack(
            alignment: alignment,
            spacing: spacing
        ) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        header
        subtitleContent
    }
}

// MARK: - Header:

private extension TitleSubtitleExpandableView {
    private var header: some View {
        ExpandableHeaderView(
            isExpanded: $isExpanded,
            title: title,
            isTitleLocalized: isTitleLocalized,
            titleFont: titleFont,
            titleTextCase: titleTextCase,
            titleAlignment: titleAlignment,
            titleLineSpacing: titleLineSpacing,
            titleColor: titleColor,
            expandButtonIcon: expandButtonIcon,
            expandButtonSymbolVariant: expandButtonSymbolVariant,
            expandButtonColor: expandButtonColor,
            expandButtonGradientStart: expandButtonGradientStart,
            expandButtonGradientEnd: expandButtonGradientEnd,
            isExpandButtonColorGradient: isExpandButtonColorGradient,
            expandButtonIconSize: expandButtonIconSize,
            alignment: titleExpandButtonAlignment,
            spacing: titleExpandButtonSpacing,
            verticalPadding: 0,
            horizontalPadding: 0,
            isExpandHapticFeedbackEnabled: isExpandHapticFeedbackEnabled
        )
    }
}

// MARK: - Subtitle:

private extension TitleSubtitleExpandableView {
    @ViewBuilder
    private var subtitleContent: some View {
        if isExpanded {
            subtitleItem
        }
    }
    
    private var subtitleItem: some View {
        subtitleItemContent
            .font(subtitleFont)
            .textCase(subtitleTextCase)
            .multilineTextAlignment(subtitleAlignment)
            .lineSpacing(subtitleLineSpacing)
            .optionalForegroundStyle(subtitleColor)
    }
    
    @ViewBuilder
    private var subtitleItemContent: some View {
        if isSubtitleLocalized {
            Text(.init(subtitle))
        } else {
            Text(subtitle)
        }
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        TitleSubtitleExpandableView(
            isExpanded: false,
            title: "Title",
            isTitleLocalized: true,
            titleFont: .headline,
            titleTextCase: .none,
            titleAlignment: .leading,
            titleLineSpacing: 0,
            titleColor: .primary,
            subtitle: "Subtitle",
            isSubtitleLocalized: true,
            subtitleFont: .subheadline,
            subtitleTextCase: .none,
            subtitleAlignment: .leading,
            subtitleLineSpacing: 0,
            subtitleColor: .secondary,
            expandButtonIcon: Icons.chevronRight,
            expandButtonSymbolVariant: .fill,
            expandButtonColor: .accent,
            expandButtonGradientStart: .blueGradientStart,
            expandButtonGradientEnd: .blueGradientEnd,
            isExpandButtonColorGradient: true,
            expandButtonIconSize: .custom(
                font: .headline,
                nonBackgroundFont: .headline,
                frame: 22,
                cornerRadius: 0,
                cornerStyle: .continuous
            ),
            titleExpandButtonAlignment: .top,
            titleExpandButtonSpacing: 12,
            alignment: .leading,
            spacing: 4,
            verticalPadding: 12,
            horizontalPadding: 12,
            maxHeight: nil,
            maxHeightAlignment: .topLeading,
            isShowingBackground: true,
            backgroundColor: .init(.secondarySystemGroupedBackground),
            backgroundGradientStart: .blueGradientStart,
            backgroundGradientEnd: .blueGradientEnd,
            isBackgroundColorGradient: false,
            cornerRadius: 16,
            cornerStyle: .continuous,
            isExpandHapticFeedbackEnabled: true
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
    .background(Color(.systemGroupedBackground))
}
