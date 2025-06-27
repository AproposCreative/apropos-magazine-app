//
//  PieChartView.swift
//  Native
//

import SwiftUI
import Charts

struct PieChartView: View {
    
    // MARK: - Private properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    /// 'Bool' value indicating whether or not the title and the value of the chart should be shown at all:
    private let isShowingTitleValue: Bool
    
    /// Title of the chart:
    private let title: String
    
    /// 'Bool' value indicating whether or not the title of the chart should be localized:
    private let isTitleLocalized: Bool
    
    /// Font of the title of the chart:
    private let titleFont: Font
    
    /// Text case of the title of the chart:
    private let titleTextCase: Text.Case?
    
    /// Alignment of the title of the chart:
    private let titleAlignment: TextAlignment
    
    /// Color of the title of the chart:
    private let titleColor: Color
    
    /// Font of the value of the chart:
    private let valueFont: Font
    
    /// Alignment of the value of the chart:
    private let valueAlignment: TextAlignment
    
    /// Color of the value of the chart:
    private let valueColor: Color
    
    /// Type of the value of the chart:
    private let valueType: NT_ChartValueType
    
    /// Alignment of the title and the value of the chart:
    private let titleValueAlignment: HorizontalAlignment
    
    /// Spacing between the title and the value of the chart:
    private let titleValueSpacing: Double
    
    /// Maximum width that the title and the value should have if applicable:
    private let titleValueMaxWidth: CGFloat?
    
    /// Alignment of the title and the value if they have a maximum width applied to them:
    private let titleValueMaxWidthAlignment: Alignment
    
    /// An array of the sectors of the chart to display:
    private let sectors: [NT_ChartSector]
    
    /// Inner radius of each of the sectors of the chart:
    private let sectorInnerRadius: MarkDimension
    
    /// Outer radius of each of the sectors of the chart:
    private let sectorOuterRadius: MarkDimension
    
    /// Angular inset of each of the sectors of the chart which is essentially the spacing between the sectors of the chart:
    private let sectorAngularInset: CGFloat?
    
    /// 'Bool' value indicating whether or not the colors of the background of the sectors of the chart should have a gradient applied to them:
    private let isSectorBackgroundGradient: Bool
    
    /// Radius of the rounded corners of the sectors of the chart:
    private let sectorCornerRadius: Double
    
    /// Style of the rounded corners of the sectors of the chart:
    private let sectorCornerStyle: RoundedCornerStyle
    
    /// Height of the chart:
    private let chartHeight: Double
    
    /// 'Bool' value indicating whether or not the legend of the chart should be shown at all:
    private let isShowingLegend: Bool
    
    /// An actual icon of each of the legend items to display:
    private let legendItemIcon: String
    
    /// Symbol variant of the icon of each of the legend items (It could be '.fill', '.circle', etc.):
    private let legendItemIconSymbolVariant: SymbolVariants
    
    /// Size of the icon of each of the legend items:
    private let legendItemIconSize: NT_IconSize
    
    /// 'Bool' value indicating whether or not the title of each of the legend items should be localized:
    private let isLegendItemTitleLocalized: Bool
    
    /// Font of the title of each of the legend items:
    private let legendItemTitleFont: Font
    
    /// Text case of the title of each of the legend items:
    private let legendItemTitleTextCase: Text.Case?
    
    /// Alignment of the title of each of the legend items:
    private let legendItemTitleAlignment: TextAlignment
    
    /// Additional spacing between the multiple lines of the title of each of the legend items:
    private let legendItemTitleLineSpacing: Double
    
    /// Color of the title of each of the legend items:
    private let legendItemTitleColor: Color
    
    /// Alignment of the content of each of the legend items:
    private let legendItemAlignment: NT_Alignment
    
    /// Vertical alignment of the content of each of the legend items:
    private let legendItemVerticalAlignment: VerticalAlignment
    
    /// Horizontal alignment of the content of each of the legend items:
    private let legendItemHorizontalAlignment: HorizontalAlignment
    
    /// Spacing between the content of each of the legend items:
    private let legendItemSpacing: Double
    
    /// Vertical padding around the content of each of the legend items:
    private let legendItemVerticalPadding: Double
    
    /// Horizontal padding around the content of each of the legend items:
    private let legendItemHorizontalPadding: Double
    
    /// 'Bool' value indicating whether or not the background of each of the legend items should be shown at all:
    private let isShowingLegendItemBackground: Bool
    
    /// Color of the background of each of the legend items:
    private let legendItemBackgroundColor: Color
    
    /// Starting color of the gradient of the background of each of the legend items if applicable:
    private let legendItemBackgroundGradientStart: Color
    
    /// Ending color of the gradient of the background of each of the legend items if applicable:
    private let legendItemBackgroundGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the background of each of the legend items should have a gradient applied to it:
    private let isLegendItemBackgroundColorGradient: Bool
    
    /// Radius of the rounded corners of each of the legend items:
    private let legendItemCornerRadius: Double
    
    /// Style of the rounded corners of each of the legend items:
    private let legendItemCornerStyle: RoundedCornerStyle
    
    /// Alignment of the legend:
    private let legendAlignment: VerticalAlignment
    
    /// Spacing between the content of the legend:
    private let legendSpacing: Double
    
    /// Alignment of the content of the view:
    private let alignment: HorizontalAlignment
    
    /// Spacing between the content of the view:
    private let spacing: Double
    
    /// Vertical padding of the content of the view:
    private let verticalPadding: Double
    
    /// Horizontal padding of the content of the view:
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
    
    init(
        isShowingTitleValue: Bool = true,
        title: String = "",
        isTitleLocalized: Bool = true,
        titleFont: Font = .footnote.weight(.bold),
        titleTextCase: Text.Case? = .uppercase,
        titleAlignment: TextAlignment = .center,
        titleColor: Color = .accent,
        valueFont: Font = .title2.bold(),
        valueAlignment: TextAlignment = .center,
        valueColor: Color = .primary,
        valueType: NT_ChartValueType = .currency(code: "USD"),
        titleValueAlignment: HorizontalAlignment = .center,
        titleValueSpacing: Double = 4,
        titleValueMaxWidth: CGFloat? = 200,
        titleValueMaxWidthAlignment: Alignment = .center,
        sectors: [NT_ChartSector],
        sectorInnerRadius: MarkDimension = .ratio(0.7),
        sectorOuterRadius: MarkDimension = .ratio(1),
        sectorAngularInset: CGFloat? = 2,
        isSectorBackgroundGradient: Bool = true,
        sectorCornerRadius: Double = 8,
        sectorCornerStyle: RoundedCornerStyle = .continuous,
        chartHeight: Double = 304,
        isShowingLegend: Bool = true,
        legendItemIcon: String = Icons.circle,
        legendItemIconSymbolVariant: SymbolVariants = .fill,
        legendItemIconSize: NT_IconSize = .sixteenPixels,
        isLegendItemTitleLocalized: Bool = true,
        legendItemTitleFont: Font = .footnote.bold(),
        legendItemTitleTextCase: Text.Case? = .none,
        legendItemTitleAlignment: TextAlignment = .leading,
        legendItemTitleLineSpacing: Double = 0,
        legendItemTitleColor: Color = .primary,
        legendItemAlignment: NT_Alignment = .horizontal,
        legendItemVerticalAlignment: VerticalAlignment = .center,
        legendItemHorizontalAlignment: HorizontalAlignment = .leading,
        legendItemSpacing: Double = 6,
        legendItemVerticalPadding: Double = 6,
        legendItemHorizontalPadding: Double = 8,
        isShowingLegendItemBackground: Bool = true,
        legendItemBackgroundColor: Color = .init(.systemGroupedBackground),
        legendItemBackgroundGradientStart: Color = .blueGradientStart,
        legendItemBackgroundGradientEnd: Color = .blueGradientEnd,
        isLegendItemBackgroundColorGradient: Bool = false,
        legendItemCornerRadius: Double = 8,
        legendItemCornerStyle: RoundedCornerStyle = .continuous,
        legendAlignment: VerticalAlignment = .top,
        legendSpacing: Double = 8,
        alignment: HorizontalAlignment = .leading,
        spacing: Double = 24,
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
        cornerStyle: RoundedCornerStyle = .continuous
    ) {
        
        /// Properties initialization:
        self.isShowingTitleValue = isShowingTitleValue
        self.title = title
        self.isTitleLocalized = isTitleLocalized
        self.titleFont = titleFont
        self.titleTextCase = titleTextCase
        self.titleAlignment = titleAlignment
        self.titleColor = titleColor
        self.valueFont = valueFont
        self.valueAlignment = valueAlignment
        self.valueColor = valueColor
        self.valueType = valueType
        self.titleValueAlignment = titleValueAlignment
        self.titleValueSpacing = titleValueSpacing
        self.titleValueMaxWidth = titleValueMaxWidth
        self.titleValueMaxWidthAlignment = titleValueMaxWidthAlignment
        self.sectors = sectors
        self.sectorInnerRadius = sectorInnerRadius
        self.sectorOuterRadius = sectorOuterRadius
        self.sectorAngularInset = sectorAngularInset
        self.isSectorBackgroundGradient = isSectorBackgroundGradient
        self.sectorCornerRadius = sectorCornerRadius
        self.sectorCornerStyle = sectorCornerStyle
        self.chartHeight = chartHeight
        self.isShowingLegend = isShowingLegend
        self.legendItemIcon = legendItemIcon
        self.legendItemIconSymbolVariant = legendItemIconSymbolVariant
        self.legendItemIconSize = legendItemIconSize
        self.isLegendItemTitleLocalized = isLegendItemTitleLocalized
        self.legendItemTitleFont = legendItemTitleFont
        self.legendItemTitleTextCase = legendItemTitleTextCase
        self.legendItemTitleAlignment = legendItemTitleAlignment
        self.legendItemTitleLineSpacing = legendItemTitleLineSpacing
        self.legendItemTitleColor = legendItemTitleColor
        self.legendItemAlignment = legendItemAlignment
        self.legendItemVerticalAlignment = legendItemVerticalAlignment
        self.legendItemHorizontalAlignment = legendItemHorizontalAlignment
        self.legendItemSpacing = legendItemSpacing
        self.legendItemVerticalPadding = legendItemVerticalPadding
        self.legendItemHorizontalPadding = legendItemHorizontalPadding
        self.isShowingLegendItemBackground = isShowingLegendItemBackground
        self.legendItemBackgroundColor = legendItemBackgroundColor
        self.legendItemBackgroundGradientStart = legendItemBackgroundGradientStart
        self.legendItemBackgroundGradientEnd = legendItemBackgroundGradientEnd
        self.isLegendItemBackgroundColorGradient = isLegendItemBackgroundColorGradient
        self.legendItemCornerRadius = legendItemCornerRadius
        self.legendItemCornerStyle = legendItemCornerStyle
        self.legendAlignment = legendAlignment
        self.legendSpacing = legendSpacing
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
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be shown at all:
    private var isShowing: Bool {
        isShowingTitleValue
        || isShowingChart
    }
    
    /// 'Bool' value indicating whether or not the chart should be shown at all:
    private var isShowingChart: Bool {
        !sectors.isEmpty
    }
    
    /// 'Bool' value indicating whether or not the content of the view should be moved that is based on the size of the dynamic type that is currently selected:
    private var shouldMoveContent: Bool {
        dynamicTypeSize >= .accessibility1
    }
    
    /// Total value of all of the sectors of the chart as a string:
    private var value: String {
        
        /// Firstly getting the value of all of the sectors of the chart:
        let value: Double = sectors.map { $0.value }.reduce(0, +)
        
        /// Then switching on the type of the value of the chart to return the right value:
        switch valueType {
        case .number:
            
            /// If it's a number, then formatting the value as a number:
            let number: String = value.formatted(.number)
            
            /// Then returning the given number as a string:
            return number
        case .currency (let code):
            
            /// If it's a currency, then formatting the value as a currency using the given currency code:
            let currency: String = value.formatted(.currency(code: code))
            
            /// Lastly returning the given currency as a string:
            return currency
        }
    }
    
    /// Value of the alignment of the title of the chart that is based on the size of the dynamic type that is currently selected:
    private var titleAlignmentValue: TextAlignment {
        shouldMoveContent ? .leading : titleAlignment
    }
    
    /// Value of the alignment of the value of the chart that is based on the size of the dynamic type that is currently selected:
    private var valueAlignmentValue: TextAlignment {
        shouldMoveContent ? .leading : valueAlignment
    }
    
    /// Value of the alignment of the title and the value of the chart that is based on the size of the dynamic type that is currently selected:
    private var titleValueAlignmentValue: HorizontalAlignment {
        shouldMoveContent ? .leading : titleValueAlignment
    }
    
    /// Value of the alignment of the title and the value if they have a maximum width applied to them that is based on the size of the dynamic type that is currently selected:
    private var titleValueMaxWidthAlignmentValue: Alignment {
        shouldMoveContent ? .leading : titleValueMaxWidthAlignment
    }
    
    /// Value of the maximum width that the title and the value should have that is based on the size of the dynamic type that is currently selected:
    private var titleValueMaxWidthValue: CGFloat? {
        shouldMoveContent ? .infinity : titleValueMaxWidth
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

private extension PieChartView {
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
        itemTitleValue
        chart
        legend
    }
    
    @ViewBuilder
    private var itemTitleValue: some View {
        if shouldMoveContent {
            titleValue
        }
    }
}

// MARK: - Title and value:

private extension PieChartView {
    @ViewBuilder
    private var titleValue: some View {
        if isShowingTitleValue {
            titleValueContent
        }
    }
    
    private var titleValueContent: some View {
        titleValueItem
            .frame(
                maxWidth: titleValueMaxWidthValue,
                alignment: titleValueMaxWidthAlignmentValue
            )
            .accessibilityElement(children: .combine)
    }
    
    private var titleValueItem: some View {
        VStack(
            alignment: titleValueAlignmentValue,
            spacing: titleValueSpacing
        ) {
            titleValueItemContent
        }
    }
    
    @ViewBuilder
    private var titleValueItemContent: some View {
        titleContent
        valueContent
    }
    
    private var titleContent: some View {
        titleItem
            .font(titleFont)
            .textCase(titleTextCase)
            .multilineTextAlignment(titleAlignmentValue)
            .foregroundStyle(titleColor)
    }
    
    @ViewBuilder
    private var titleItem: some View {
        if isTitleLocalized {
            Text(.init(title))
        } else {
            Text(title)
        }
    }
    
    private var valueContent: some View {
        Text(value)
            .font(valueFont)
            .multilineTextAlignment(valueAlignmentValue)
            .foregroundStyle(valueColor)
    }
}

// MARK: - Chart:

private extension PieChartView {
    @ViewBuilder
    private var chart: some View {
        if isShowingChart {
            chartContent
        }
    }
    
    private var chartContent: some View {
        chartItem
            .chartBackground { _ in
                chartTitleValue
            }
            .frame(
                height: chartHeight,
                alignment: .center
            )
            .accessibilityElement(children: .combine)
    }
    
    @ViewBuilder
    private var chartTitleValue: some View {
        if !shouldMoveContent {
            titleValue
        }
    }
    
    private var chartItem: some View {
        Chart {
            chartSectorsContent
        }
    }
    
    private var chartSectorsContent: some ChartContent {
        ForEach(
            sectors,
            content: chartSector
        )
    }
    
    private func chartSector(_ sector: NT_ChartSector) -> some ChartContent {
        chartSectorContent(sector)
            .cornerRadius(
                sectorCornerRadius,
                style: sectorCornerStyle
            )
            .accessibilityValue(accessibilityValue(sector))
    }
    
    @ChartContentBuilder
    private func chartSectorContent(_ sector: NT_ChartSector) -> some ChartContent {
        if isSectorBackgroundGradient {
            gradientSectorItem(sector)
        } else {
            colorSectorItem(sector)
        }
    }
    
    private func gradientSectorItem(_ sector: NT_ChartSector) -> some ChartContent {
        sectorItem(sector)
            .foregroundStyle(gradient(sector))
    }
    
    private func colorSectorItem(_ sector: NT_ChartSector) -> some ChartContent {
        sectorItem(sector)
            .foregroundStyle(color(sector))
    }
    
    private func sectorItem(_ sector: NT_ChartSector) -> some ChartContent {
        SectorMark(
            angle: .value(
                valueTitle(sector),
                value(sector)
            ),
            innerRadius: sectorInnerRadius,
            outerRadius: sectorOuterRadius,
            angularInset: sectorAngularInset
        )
    }
}

// MARK: - Legend:

private extension PieChartView {
    @ViewBuilder
    private var legend: some View {
        if isShowingLegend {
            legendScroll
        }
    }
    
    private var legendScroll: some View {
        legendScrollContent
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
    }
    
    private var legendScrollContent: some View {
        ScrollView(.horizontal) {
            legendScrollItem
        }
    }
    
    private var legendScrollItem: some View {
        legendItems
            .scrollTargetLayout()
    }
    
    private var legendItems: some View {
        LazyHStack(
            alignment: legendAlignment,
            spacing: legendSpacing
        ) {
            legendItemsContent
        }
    }
    
    private var legendItemsContent: some View {
        ForEach(
            sectors,
            content: legendItem
        )
    }
    
    private func legendItem(_ sector: NT_ChartSector) -> some View {
        IconBackgroundTitleSubtitleView(
            icon: legendItemIcon,
            iconSymbolVariant: legendItemIconSymbolVariant,
            iconColor: color(sector),
            iconGradientStart: gradientStart(sector),
            iconGradientEnd: gradientEnd(sector),
            isIconColorGradient: isSectorBackgroundGradient,
            isShowingIconBackground: false,
            iconSize: legendItemIconSize,
            title: valueTitle(sector),
            isTitleLocalized: isLegendItemTitleLocalized,
            titleFont: legendItemTitleFont,
            titleTextCase: legendItemTitleTextCase,
            titleAlignment: legendItemTitleAlignment,
            titleLineSpacing: legendItemTitleLineSpacing,
            titleColor: legendItemTitleColor,
            isShowingSubtitle: false,
            subtitle: "",
            alignment: legendItemAlignment,
            verticalAlignment: legendItemVerticalAlignment,
            horizontalAlignment: legendItemHorizontalAlignment,
            spacing: legendItemSpacing,
            verticalPadding: legendItemVerticalPadding,
            horizontalPadding: legendItemHorizontalPadding,
            isShowingBackground: isShowingLegendItemBackground,
            backgroundColor: legendItemBackgroundColor,
            backgroundGradientStart: legendItemBackgroundGradientStart,
            backgroundGradientEnd: legendItemBackgroundGradientEnd,
            isBackgroundColorGradient: isLegendItemBackgroundColorGradient,
            cornerRadius: legendItemCornerRadius,
            cornerStyle: legendItemCornerStyle
        )
    }
}

// MARK: - Functions:

private extension PieChartView {
    
    // MARK: - Private functions:
    
    /// Returns the title of the value for the given sector of the chart:
    private func valueTitle(_ sector: NT_ChartSector) -> String {
        sector.valueTitle
    }
    
    /// Returns the value for the given sector of the chart:
    private func value(_ sector: NT_ChartSector) -> Double {
        sector.value
    }
    
    /// Returns the accessibility value for the given sector of the chart that is needed for the VoiceOver:
    private func accessibilityValue(_ sector: NT_ChartSector) -> String {
        
        /// Firstly getting the value of the given sector of the chart:
        let value: Double = value(sector)
        
        /// Then switching on the type of the value of the chart to return the right value:
        switch valueType {
        case .number:
            
            /// If it's a number, then formatting the value as a number:
            let number: String = value.formatted(.number)
            
            /// Then returning the given number as a string:
            return number
        case .currency (let code):
            
            /// If it's a currency, then formatting the value as a currency using the given currency code:
            let currency: String = value.formatted(.currency(code: code))
            
            /// Lastly returning the given currency as a string:
            return currency
        }
    }
    
    /// Returns the color for the given sector of the chart:
    private func color(_ sector: NT_ChartSector) -> Color {
        sector.color
    }
    
    /// Returns the starting color of the gradient for the given sector of the chart:
    private func gradientStart(_ sector: NT_ChartSector) -> Color {
        sector.gradientStart
    }
    
    /// Returns the ending color of the gradient for the given sector of the chart:
    private func gradientEnd(_ sector: NT_ChartSector) -> Color {
        sector.gradientEnd
    }
    
    /// Returns the gradient for the given sector of the chart:
    private func gradient(_ sector: NT_ChartSector) -> LinearGradient {
        .init(
            colors: [
                gradientStart(sector),
                gradientEnd(sector)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        PieChartView(
            isShowingTitleValue: true,
            title: "Title",
            isTitleLocalized: true,
            titleFont: .footnote.weight(.bold),
            titleTextCase: .uppercase,
            titleAlignment: .center,
            titleColor: .accent,
            valueFont: .title2.bold(),
            valueAlignment: .center,
            valueColor: .primary,
            valueType: .currency(code: "USD"),
            titleValueAlignment: .center,
            titleValueSpacing: 4,
            titleValueMaxWidth: 200,
            titleValueMaxWidthAlignment: .center,
            sectors: NT_ChartSector.example,
            sectorInnerRadius: .ratio(0.7),
            sectorOuterRadius: .ratio(1),
            sectorAngularInset: 2,
            isSectorBackgroundGradient: true,
            sectorCornerRadius: 8,
            sectorCornerStyle: .continuous,
            chartHeight: 304,
            isShowingLegend: true,
            legendItemIcon: Icons.circle,
            legendItemIconSymbolVariant: .fill,
            legendItemIconSize: .sixteenPixels,
            isLegendItemTitleLocalized: true,
            legendItemTitleFont: .footnote.bold(),
            legendItemTitleTextCase: .none,
            legendItemTitleAlignment: .leading,
            legendItemTitleLineSpacing: 0,
            legendItemTitleColor: .primary,
            legendItemAlignment: .horizontal,
            legendItemVerticalAlignment: .center,
            legendItemHorizontalAlignment: .leading,
            legendItemSpacing: 6,
            legendItemVerticalPadding: 6,
            legendItemHorizontalPadding: 8,
            isShowingLegendItemBackground: true,
            legendItemBackgroundColor: .init(.systemGroupedBackground),
            legendItemBackgroundGradientStart: .blueGradientStart,
            legendItemBackgroundGradientEnd: .blueGradientEnd,
            isLegendItemBackgroundColorGradient: false,
            legendItemCornerRadius: 8,
            legendItemCornerStyle: .continuous,
            legendAlignment: .top,
            legendSpacing: 8,
            alignment: .leading,
            spacing: 24,
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
