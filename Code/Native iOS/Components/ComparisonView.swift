//
//  ComparisonView.swift
//  Native
//

import SwiftUI

struct ComparisonView: View {
    
    // MARK: - Private properties:
    
    /// An array of the rows to display in the table for the comparison:
    private let rows: [NT_ComparisonRow]
    
    /// Font of each of the titles of the rows:
    private let titleFont: Font
    
    /// Text case of each of the titles of the rows:
    private let titleTextCase: Text.Case?
    
    /// Alignment of each of the titles of the rows:
    private let titleAlignment: TextAlignment
    
    /// Additional spacing between the multiple lines of each of the titles of the rows:
    private let titleLineSpacing: Double
    
    /// Color of each of the titles of the rows:
    private let titleColor: Color?
    
    /// Maximum width that the frame of the titles of each of the rows should have:
    private let titleMaxWidth: CGFloat?
    
    /// Alignment of the frame of each of the titles of the rows:
    private let titleFrameAlignment: Alignment
    
    /// An actual icon for when the item of the row for the comparison is included to display:
    private let includedIcon: String
    
    /// Symbol variant of the icon for when the item of the row for the comparison is included (It could be '.fill', '.circle', etc.):
    private let includedIconSymbolVariant: SymbolVariants
    
    /// Font of the icon for when the item of the row for the comparison is included:
    private let includedIconFont: Font
    
    /// Color of the icon for when the item of the row for the comparison is included:
    private let includedIconColor: Color
    
    /// Starting color of the gradient of the icon for when the item of the row for the comparison is included if applicable:
    private let includedIconGradientStart: Color
    
    /// Ending color of the gradient of the icon for when the item of the row for the comparison is included if applicable:
    private let includedIconGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the icon for when the item of the row for the comparison is included should have a gradient applied to it:
    private let isIncludedIconColorGradient: Bool
    
    /// Size of the frame of the icon for when the item of the row for the comparison is included if applicable:
    private let includedIconFrame: CGFloat?
    
    /// An actual icon for when the item of the row for the comparison is excluded to display:
    private let excludedIcon: String
    
    /// Symbol variant of the icon for when the item of the row for the comparison is excluded (It could be '.fill', '.circle', etc.):
    private let excludedIconSymbolVariant: SymbolVariants
    
    /// Font of the icon for when the item of the row for the comparison is excluded:
    private let excludedIconFont: Font
    
    /// Color of the icon for when the item of the row for the comparison is excluded:
    private let excludedIconColor: Color
    
    /// Starting color of the gradient of the icon for when the item of the row for the comparison is excluded if applicable:
    private let excludedIconGradientStart: Color
    
    /// Ending color of the gradient of the icon for when the item of the row for the comparison is excluded if applicable:
    private let excludedIconGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the icon for when the item of the row for the comparison is excluded should have a gradient applied to it:
    private let isExcludedIconColorGradient: Bool
    
    /// Size of the frame of the icon for when the item of the row for the comparison is excluded if applicable:
    private let excludedIconFrame: CGFloat?
    
    /// Alignment of each of the rows:
    private let rowAlignment: VerticalAlignment
    
    /// Spacing between the content of each of the rows:
    private let rowSpacing: Double
    
    /// Maximum width that the frame of each of the rows should have:
    private let rowMaxWidth: CGFloat?
    
    /// Alignment of the frame of each of the rows:
    private let rowFrameAlignment: Alignment
    
    /// Vertical padding around the content of each of the rows:
    private let rowVerticalPadding: Double
    
    /// Horizontal padding around the content of each of the rows:
    private let rowHorizontalPadding: Double
    
    /// 'Bool' value indicating whether or not the background of each of the rows should be shown at all:
    private let isShowingRowBackground: Bool
    
    /// Color of the background of each of the rows:
    private let rowBackgroundColor: Color
    
    /// Starting color of the gradient of the background of each of the rows if applicable:
    private let rowBackgroundGradientStart: Color
    
    /// Ending color of the gradient of the background of each of the rows if applicable:
    private let rowBackgroundGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the background of each of the rows should have a gradient applied to it:
    private let isRowBackgroundColorGradient: Bool
    
    /// Radius of the rounded corners of each of the rows:
    private let rowCornerRadius: Double
    
    /// Style of the rounded corners of each of the rows:
    private let rowCornerStyle: RoundedCornerStyle
    
    /// Spacing between the content of the view:
    private let spacing: Double
    
    /// 'Bool' value indicating whether or not the content of the view should be scrollable:
    private let isScrollable: Bool
    
    /// Alignment of the view:
    private let alignment: HorizontalAlignment
    
    /// Maximum width that the frame of the view should have:
    private let maxWidth: CGFloat?
    
    /// Alignment of the frame of the view:
    private let frameAlignment: Alignment
    
    /// Vertical padding around the content of the view:
    private let verticalPadding: Double
    
    /// Horizontal padding around the content of the view:
    private let horizontalPadding: Double
    
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
    
    init(
        rows: [NT_ComparisonRow],
        titleFont: Font = .subheadline.bold(),
        titleTextCase: Text.Case? = .none,
        titleAlignment: TextAlignment = .leading,
        titleLineSpacing: Double = 0,
        titleColor: Color? = .primary,
        titleMaxWidth: CGFloat? = .infinity,
        titleFrameAlignment: Alignment = .leading,
        includedIcon: String = Icons.checkmarkCircle,
        includedIconSymbolVariant: SymbolVariants = .circle.fill,
        includedIconFont: Font = .system(
            size: 15,
            weight: .semibold,
            design: .default
        ),
        includedIconColor: Color = .green,
        includedIconGradientStart: Color = .greenGradientStart,
        includedIconGradientEnd: Color = .greenGradientEnd,
        isIncludedIconColorGradient: Bool = true,
        includedIconFrame: CGFloat? = 20,
        excludedIcon: String = Icons.xmarkCircle,
        excludedIconSymbolVariant: SymbolVariants = .fill,
        excludedIconFont: Font = .system(
            size: 15,
            weight: .semibold,
            design: .default
        ),
        excludedIconColor: Color = .pink,
        excludedIconGradientStart: Color = .pinkGradientStart,
        excludedIconGradientEnd: Color = .pinkGradientEnd,
        isExcludedIconColorGradient: Bool = true,
        excludedIconFrame: CGFloat? = 20,
        rowAlignment: VerticalAlignment = .center,
        rowSpacing: Double = 12,
        rowMaxWidth: CGFloat? = 56,
        rowFrameAlignment: Alignment = .leading,
        rowVerticalPadding: Double = 12,
        rowHorizontalPadding: Double = 12,
        isShowingRowBackground: Bool = false,
        rowBackgroundColor: Color = .init(.secondarySystemGroupedBackground),
        rowBackgroundGradientStart: Color = .blueGradientStart,
        rowBackgroundGradientEnd: Color = .blueGradientEnd,
        isRowBackgroundColorGradient: Bool = false,
        rowCornerRadius: Double = 0,
        rowCornerStyle: RoundedCornerStyle = .continuous,
        spacing: Double = 0,
        isScrollable: Bool = false,
        alignment: HorizontalAlignment = .leading,
        maxWidth: CGFloat? = .infinity,
        frameAlignment: Alignment = .leading,
        verticalPadding: Double = 12,
        horizontalPadding: Double = 12,
        isShowingBackground: Bool = true,
        backgroundColor: Color = .init(.secondarySystemGroupedBackground),
        backgroundGradientStart: Color = .blueGradientStart,
        backgroundGradientEnd: Color = .blueGradientEnd,
        isBackgroundColorGradient: Bool = false,
        cornerRadius: Double = 16,
        cornerStyle: RoundedCornerStyle = .continuous
    ) {
        
        /// Properties initialization:
        self.rows = rows
        self.titleFont = titleFont
        self.titleTextCase = titleTextCase
        self.titleAlignment = titleAlignment
        self.titleLineSpacing = titleLineSpacing
        self.titleColor = titleColor
        self.titleMaxWidth = titleMaxWidth
        self.titleFrameAlignment = titleFrameAlignment
        self.includedIcon = includedIcon
        self.includedIconSymbolVariant = includedIconSymbolVariant
        self.includedIconFont = includedIconFont
        self.includedIconColor = includedIconColor
        self.includedIconGradientStart = includedIconGradientStart
        self.includedIconGradientEnd = includedIconGradientEnd
        self.isIncludedIconColorGradient = isIncludedIconColorGradient
        self.includedIconFrame = includedIconFrame
        self.excludedIcon = excludedIcon
        self.excludedIconSymbolVariant = excludedIconSymbolVariant
        self.excludedIconFont = excludedIconFont
        self.excludedIconColor = excludedIconColor
        self.excludedIconGradientStart = excludedIconGradientStart
        self.excludedIconGradientEnd = excludedIconGradientEnd
        self.isExcludedIconColorGradient = isExcludedIconColorGradient
        self.excludedIconFrame = excludedIconFrame
        self.rowAlignment = rowAlignment
        self.rowSpacing = rowSpacing
        self.rowMaxWidth = rowMaxWidth
        self.rowFrameAlignment = rowFrameAlignment
        self.rowVerticalPadding = rowVerticalPadding
        self.rowHorizontalPadding = rowHorizontalPadding
        self.isShowingRowBackground = isShowingRowBackground
        self.rowBackgroundColor = rowBackgroundColor
        self.rowBackgroundGradientStart = rowBackgroundGradientStart
        self.rowBackgroundGradientEnd = rowBackgroundGradientEnd
        self.isRowBackgroundColorGradient = isRowBackgroundColorGradient
        self.rowCornerRadius = rowCornerRadius
        self.rowCornerStyle = rowCornerStyle
        self.spacing = spacing
        self.isScrollable = isScrollable
        self.alignment = alignment
        self.maxWidth = maxWidth
        self.frameAlignment = frameAlignment
        self.verticalPadding = verticalPadding
        self.horizontalPadding = horizontalPadding
        self.isShowingBackground = isShowingBackground
        self.backgroundColor = backgroundColor
        self.backgroundGradientStart = backgroundGradientStart
        self.backgroundGradientEnd = backgroundGradientEnd
        self.isBackgroundColorGradient = isBackgroundColorGradient
        self.cornerRadius = cornerRadius
        self.cornerStyle = cornerStyle
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be shown at all:
    private var isShowing: Bool {
        !rows.isEmpty
    }
    
    /// Accessibility label of the item of the row for the comparison when it's included:
    private var includedAccessibilityLabel: LocalizedStringKey {
        "Included"
    }
    
    /// Accessibility label of the item of the row for the comparison when it's excluded:
    private var excludedAccessibilityLabel: LocalizedStringKey {
        "Excluded"
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    @ViewBuilder
    private var content: some View {
        if isShowing {
            mainContent
        }
    }
    
    private var mainContent: some View {
        item
            .frame(
                maxWidth: maxWidth,
                alignment: frameAlignment
            )
            .contentBackground(
                verticalPadding: verticalPadding,
                horizontalPadding: horizontalPadding,
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

private extension ComparisonView {
    @ViewBuilder
    private var item: some View {
        if isScrollable {
            itemScroll
        } else {
            itemContent
        }
    }
    
    private var itemScroll: some View {
        ScrollView(.horizontal) {
            itemContent
        }
    }
    
    private var itemContent: some View {
        VStack(
            alignment: alignment,
            spacing: spacing
        ) {
            rowsContent
        }
    }
}

// MARK: - Rows:

private extension ComparisonView {
    private var rowsContent: some View {
        ForEach(
            rows,
            content: row
        )
    }
    
    private func row(_ row: NT_ComparisonRow) -> some View {
        rowContent(row)
            .contentBackground(
                verticalPadding: rowVerticalPadding,
                horizontalPadding: rowHorizontalPadding,
                isShowingBackground: isShowingRowBackground,
                backgroundColor: rowBackgroundColor,
                backgroundGradientStart: rowBackgroundGradientStart,
                backgroundGradientEnd: rowBackgroundGradientEnd,
                isBackgroundColorGradient: isRowBackgroundColorGradient,
                cornerRadius: rowCornerRadius,
                cornerStyle: rowCornerStyle
            )
    }
    
    private func rowContent(_ row: NT_ComparisonRow) -> some View {
        rowItem(row)
            .accessibilityElement(children: .combine)
    }
    
    private func rowItem(_ row: NT_ComparisonRow) -> some View {
        HStack(
            alignment: rowAlignment,
            spacing: rowSpacing
        ) {
            rowItemContent(row)
        }
    }
    
    @ViewBuilder
    private func rowItemContent(_ row: NT_ComparisonRow) -> some View {
        rowTitleContent(row)
        rowItemsContent(row)
    }
    
    private func rowTitleContent(_ row: NT_ComparisonRow) -> some View {
        rowTitleItem(row)
            .font(titleFont)
            .textCase(titleTextCase)
            .multilineTextAlignment(titleAlignment)
            .lineSpacing(titleLineSpacing)
            .optionalForegroundStyle(titleColor)
            .frame(
                maxWidth: titleMaxWidth,
                alignment: titleFrameAlignment
            )
    }
    
    @ViewBuilder
    private func rowTitleItem(_ row: NT_ComparisonRow) -> some View {
        if isRowTitleLocalized(row) {
            Text(.init(rowTitle(row)))
        } else {
            Text(rowTitle(row))
        }
    }
}

// MARK: - Row items:

private extension ComparisonView {
    private func rowItemsContent(_ row: NT_ComparisonRow) -> some View {
        ForEach(
            rowItems(row),
            content: rowItem
        )
    }
    
    private func rowItem(_ item: NT_ComparisonRowItem) -> some View {
        rowItemContent(item)
            .frame(
                maxWidth: rowMaxWidth,
                alignment: rowFrameAlignment
            )
    }
    
    @ViewBuilder
    private func rowItemContent(_ item: NT_ComparisonRowItem) -> some View {
        switch rowItemType(item) {
        case .none:
            EmptyView()
        case .header (
            let title,
            let isTitleLocalized
        ):
            headerRowItem(
                withTitle: title,
                isTitleLocalized: isTitleLocalized
            )
        case .included:
            includedRowItem()
        case .excluded:
            excludedRowItem()
        }
    }
    
    private func headerRowItem(
        withTitle title: String,
        isTitleLocalized: Bool
    ) -> some View {
        headerRowItemContent(
            withTitle: title,
            isTitleLocalized: isTitleLocalized
        )
        .font(titleFont)
        .textCase(titleTextCase)
        .multilineTextAlignment(titleAlignment)
        .lineSpacing(titleLineSpacing)
        .optionalForegroundStyle(titleColor)
    }
    
    @ViewBuilder
    private func headerRowItemContent(
        withTitle title: String,
        isTitleLocalized: Bool
    ) -> some View {
        if isTitleLocalized {
            Text(.init(title))
        } else {
            Text(title)
        }
    }
    
    private func includedRowItem() -> some View {
        Image(systemName: includedIcon)
            .symbolVariant(includedIconSymbolVariant)
            .font(includedIconFont)
            .foregroundGradient(
                color: includedIconColor,
                gradientStart: includedIconGradientStart,
                gradientEnd: includedIconGradientEnd,
                isGradient: isIncludedIconColorGradient
            )
            .frame(
                width: includedIconFrame,
                height: includedIconFrame,
                alignment: .center
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(includedAccessibilityLabel)
    }
    
    private func excludedRowItem() -> some View {
        Image(systemName: excludedIcon)
            .symbolVariant(excludedIconSymbolVariant)
            .font(excludedIconFont)
            .foregroundGradient(
                color: excludedIconColor,
                gradientStart: excludedIconGradientStart,
                gradientEnd: excludedIconGradientEnd,
                isGradient: isExcludedIconColorGradient
            )
            .frame(
                width: excludedIconFrame,
                height: excludedIconFrame,
                alignment: .center
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(excludedAccessibilityLabel)
    }
}

// MARK: - Functions:

private extension ComparisonView {
    
    // MARK: - Private functions:
    
    /// Returns the title of the given row for the comparison:
    private func rowTitle(_ row: NT_ComparisonRow) -> String {
        row.title
    }
    
    /// Returns a 'Bool' value indicating whether or not the title of the given row for the comparison should be localized:
    private func isRowTitleLocalized(_ row: NT_ComparisonRow) -> Bool {
        row.isTitleLocalized
    }
    
    /// Returns an array of the items of the given row to compare:
    private func rowItems(_ row: NT_ComparisonRow) -> [NT_ComparisonRowItem] {
        row.items
    }
    
    /// Returns the type of the item of the given row for the comparison
    private func rowItemType(_ item: NT_ComparisonRowItem) -> NT_ComparisonRowType {
        item.type
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        ComparisonView(
            rows: NT_ComparisonRow.example,
            titleFont: .subheadline.bold(),
            titleTextCase: .none,
            titleAlignment: .leading,
            titleLineSpacing: 0,
            titleColor: .primary,
            titleMaxWidth: .infinity,
            titleFrameAlignment: .leading,
            includedIcon: Icons.checkmarkCircle,
            includedIconSymbolVariant: .circle.fill,
            includedIconFont: .system(
                size: 15,
                weight: .semibold,
                design: .default
            ),
            includedIconColor: .green,
            includedIconGradientStart: .greenGradientStart,
            includedIconGradientEnd: .greenGradientEnd,
            isIncludedIconColorGradient: true,
            includedIconFrame: 20,
            excludedIcon: Icons.xmarkCircle,
            excludedIconSymbolVariant: .fill,
            excludedIconFont: .system(
                size: 15,
                weight: .semibold,
                design: .default
            ),
            excludedIconColor: .pink,
            excludedIconGradientStart: .pinkGradientStart,
            excludedIconGradientEnd: .pinkGradientEnd,
            isExcludedIconColorGradient: true,
            excludedIconFrame: 20,
            rowAlignment: .center,
            rowSpacing: 12,
            rowMaxWidth: 56,
            rowFrameAlignment: .leading,
            rowVerticalPadding: 12,
            rowHorizontalPadding: 12,
            isShowingRowBackground: false,
            rowBackgroundColor: .init(.secondarySystemGroupedBackground),
            rowBackgroundGradientStart: .blueGradientStart,
            rowBackgroundGradientEnd: .blueGradientEnd,
            isRowBackgroundColorGradient: false,
            rowCornerRadius: 0,
            rowCornerStyle: .continuous,
            spacing: 0,
            isScrollable: false,
            alignment: .leading,
            maxWidth: .infinity,
            frameAlignment: .leading,
            verticalPadding: 12,
            horizontalPadding: 12,
            isShowingBackground: true,
            backgroundColor: .init(.secondarySystemGroupedBackground),
            backgroundGradientStart: .blueGradientStart,
            backgroundGradientEnd: .blueGradientEnd,
            isBackgroundColorGradient: false,
            cornerRadius: 16,
            cornerStyle: .continuous
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
