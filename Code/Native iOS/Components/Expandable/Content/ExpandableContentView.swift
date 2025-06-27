//
//  ExpandableContentView.swift
//  Native
//

import SwiftUI

struct ExpandableContentView<Content: View>: View {
    
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
    
    /// Radius of the rounded corners of the view:
    private let cornerRadius: Double
    
    /// Style of the rounded corners of the view:
    private let cornerStyle: RoundedCornerStyle
    
    /// 'Bool' value indicating whether or not the haptic feedback should be triggered after expanding or collapsing the content:
    private let isExpandHapticFeedbackEnabled: Bool
    
    /// Content to display when the view is expanded:
    private let expandableContent: Content
    
    init(
        isExpanded: Bool = false,
        title: String,
        isTitleLocalized: Bool = true,
        titleFont: Font = .title3.bold(),
        titleTextCase: Text.Case? = .none,
        titleAlignment: TextAlignment = .leading,
        titleLineSpacing: Double = 0,
        titleColor: Color? = .primary,
        expandButtonIcon: String = Icons.chevronRight,
        expandButtonSymbolVariant: SymbolVariants = .fill,
        expandButtonColor: Color = .accent,
        expandButtonGradientStart: Color = .blueGradientStart,
        expandButtonGradientEnd: Color = .blueGradientEnd,
        isExpandButtonColorGradient: Bool = true,
        expandButtonIconSize: NT_IconSize = .custom(
            font: .headline,
            nonBackgroundFont: .headline,
            frame: 25,
            cornerRadius: 0,
            cornerStyle: .continuous
        ),
        titleExpandButtonAlignment: VerticalAlignment = .top,
        titleExpandButtonSpacing: Double = 12,
        alignment: HorizontalAlignment = .leading,
        spacing: Double = 16,
        verticalPadding: Double = 0,
        horizontalPadding: Double = 0,
        maxHeight: CGFloat? = nil,
        maxHeightAlignment: Alignment = .topLeading,
        isShowingBackground: Bool = false,
        backgroundColor: Color = .init(.secondarySystemGroupedBackground),
        cornerRadius: Double = 0,
        cornerStyle: RoundedCornerStyle = .continuous,
        isExpandHapticFeedbackEnabled: Bool = true,
        @ViewBuilder
        expandableContent: @escaping () -> Content
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
        self.cornerRadius = cornerRadius
        self.cornerStyle = cornerStyle
        self.isExpandHapticFeedbackEnabled = isExpandHapticFeedbackEnabled
        self.expandableContent = expandableContent()
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
                cornerRadius: cornerRadius,
                cornerStyle: cornerStyle
            )
    }
}

// MARK: - Item:

private extension ExpandableContentView {
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
        expandableItem
    }
}

// MARK: - Header:

private extension ExpandableContentView {
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

// MARK: - Expandable:

private extension ExpandableContentView {
    @ViewBuilder
    private var expandableItem: some View {
        if isExpanded {
            expandableContent
        }
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        ExpandableContentView(
            isExpanded: false,
            title: "Title",
            isTitleLocalized: true,
            titleFont: .title3.bold(),
            titleTextCase: .none,
            titleAlignment: .leading,
            titleLineSpacing: 0,
            titleColor: .primary,
            expandButtonIcon: Icons.chevronRight,
            expandButtonSymbolVariant: .fill,
            expandButtonColor: .accent,
            expandButtonGradientStart: .blueGradientStart,
            expandButtonGradientEnd: .blueGradientEnd,
            isExpandButtonColorGradient: true,
            expandButtonIconSize: .custom(
                font: .headline,
                nonBackgroundFont: .headline,
                frame: 25,
                cornerRadius: 0,
                cornerStyle: .continuous
            ),
            titleExpandButtonAlignment: .top,
            titleExpandButtonSpacing: 12,
            alignment: .leading,
            spacing: 6,
            verticalPadding: 0,
            horizontalPadding: 0,
            maxHeight: nil,
            maxHeightAlignment: .topLeading,
            isShowingBackground: false,
            backgroundColor: .init(.secondarySystemGroupedBackground),
            cornerRadius: 0,
            cornerStyle: .continuous,
            isExpandHapticFeedbackEnabled: true
        ) {
            Text("Content")
                .font(.body)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.secondary)
        }
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
