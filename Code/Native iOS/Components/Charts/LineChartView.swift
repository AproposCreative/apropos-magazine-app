//
//  LineChartView.swift
//  Native
//

import SwiftUI
import Charts

struct LineChartView<HeaderContent: View>: View {
    
    // MARK: - Private properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    /// 'Bool' value indicating whether or not the header of the chart should be shown at all:
    private let isShowingHeader: Bool
    
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
    
    /// Type of the total value of the chart:
    private let totalValueType: NT_LineChartTotalValueType
    
    /// Alignment of the title and the value of the chart:
    private let titleValueAlignment: HorizontalAlignment
    
    /// Spacing between the title and the value of the chart:
    private let titleValueSpacing: Double
    
    /// Alignment of the header of the chart:
    private let headerAlignment: VerticalAlignment
    
    /// Spacing between the content of the header of the chart:
    private let headerSpacing: Double
    
    /// An array of the lines of the chart to display:
    private let lines: [NT_ChartLine]
    
    /// Title of the X-axis of the chart:
    private let xAxisTitle: LocalizedStringKey
    
    /// Title of the Y-axis of the chart:
    private let yAxisTitle: LocalizedStringKey
    
    /// Style of each of the lines of the chart:
    private let lineStyle: StrokeStyle
    
    /// 'Bool' value indicating whether or not the symbol of each of the values of the line should be shown at all:
    private let isShowingLineValueSymbol: Bool
    
    /// Radius of the rounded corners of the symbol of each of the values of the line if applicable:
    private let lineValueSymbolCornerRadius: Double
    
    /// Style of the rounded corners of the symbol of each of the values of the line if applicable:
    private let lineValueSymbolCornerStyle: RoundedCornerStyle
    
    /// Frame of the symbol of each of the values of the line if applicable:
    private let lineValueSymbolFrame: Double
    
    /// Width of the border of each of the values of the line if applicable:
    private let lineValueSymbolBorderWidth: Double
    
    /// 'Bool' value indicating whether or not the colors of the lines of the chart should have a gradient applied to them:
    private let isLineColorGradient: Bool
    
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
    
    /// Content to display in the header if applicable:
    private let headerContent: HeaderContent
    
    init(
        isShowingHeader: Bool = true,
        title: String = "",
        isTitleLocalized: Bool = true,
        titleFont: Font = .footnote.weight(.bold),
        titleTextCase: Text.Case? = .uppercase,
        titleAlignment: TextAlignment = .leading,
        titleColor: Color = .accent,
        valueFont: Font = .title2.bold(),
        valueAlignment: TextAlignment = .leading,
        valueColor: Color = .primary,
        valueType: NT_ChartValueType = .currency(code: "USD"),
        totalValueType: NT_LineChartTotalValueType = .allValues,
        titleValueAlignment: HorizontalAlignment = .leading,
        titleValueSpacing: Double = 4,
        headerAlignment: VerticalAlignment = .top,
        headerSpacing: Double = 12,
        lines: [NT_ChartLine],
        xAxisTitle: LocalizedStringKey,
        yAxisTitle: LocalizedStringKey,
        lineStyle: StrokeStyle = .init(
            lineWidth: 2,
            lineCap: .round,
            lineJoin: .round
        ),
        isShowingLineValueSymbol: Bool = true,
        lineValueSymbolCornerRadius: Double = 8,
        lineValueSymbolCornerStyle: RoundedCornerStyle = .continuous,
        lineValueSymbolFrame: Double = 8,
        lineValueSymbolBorderWidth: Double = 2,
        isLineColorGradient: Bool = true,
        chartHeight: Double = 200,
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
        cornerStyle: RoundedCornerStyle = .continuous,
        @ViewBuilder
        headerContent: @escaping () -> HeaderContent
    ) {
        
        /// Properties initialization:
        self.isShowingHeader = isShowingHeader
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
        self.totalValueType = totalValueType
        self.titleValueAlignment = titleValueAlignment
        self.titleValueSpacing = titleValueSpacing
        self.headerAlignment = headerAlignment
        self.headerSpacing = headerSpacing
        self.lines = lines
        self.xAxisTitle = xAxisTitle
        self.yAxisTitle = yAxisTitle
        self.lineStyle = lineStyle
        self.isShowingLineValueSymbol = isShowingLineValueSymbol
        self.lineValueSymbolCornerRadius = lineValueSymbolCornerRadius
        self.lineValueSymbolCornerStyle = lineValueSymbolCornerStyle
        self.lineValueSymbolFrame = lineValueSymbolFrame
        self.lineValueSymbolBorderWidth = lineValueSymbolBorderWidth
        self.isLineColorGradient = isLineColorGradient
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
        self.headerContent = headerContent()
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be shown at all:
    private var isShowing: Bool {
        isShowingHeader
        || isShowingChart
    }
    
    /// 'Bool' value indicating whether or not the chart should be shown at all:
    private var isShowingChart: Bool {
        !lines.isEmpty
    }
    
    /// 'Bool' value indicating whether or not the content of the view should be moved that is based on the size of the dynamic type that is currently selected:
    private var shouldMoveContent: Bool {
        dynamicTypeSize >= .accessibility1
    }
    
    /// Total value of all of the sectors of the chart as a string:
    private var value: String {
        switch valueType {
        case .number: return totalValue.formatted(.number)
        case .currency (let code): return totalValue.formatted(.currency(code: code))
        }
    }
    
    /// Total value of the chart:
    private var totalValue: Double {
        switch totalValueType {
        case .allValues:
            return lines.flatMap { line in
                line.values.map {
                    $0.value
                }
            }.reduce(0, +)
        case .firstValue:
            return lines.compactMap {
                $0.values.first?.value
            }.reduce(0, +)
        case .lastValue:
            return lines.compactMap {
                $0.values.last?.value
            }.reduce(0, +)
        case .smallestValue:
            return lines.compactMap { line in
                line.values.map {
                    $0.value
                }.min()
            }.reduce(0, +)
        case .largestValue:
            return lines.compactMap { line in
                line.values.map {
                    $0.value
                }.max()
            }.reduce(0, +)
        }
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

private extension LineChartView {
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
        chart
        legend
    }
}

// MARK: - Header:

private extension LineChartView {
    @ViewBuilder
    private var header: some View {
        if isShowingHeader {
            headerItem
        }
    }
    
    @ViewBuilder
    private var headerItem: some View {
        if shouldMoveContent {
            verticalHeaderItem
        } else {
            horizontalHeaderItem
        }
    }
    
    private var horizontalHeaderItem: some View {
        HStack(
            alignment: headerAlignment,
            spacing: headerSpacing
        ) {
            headerItemContent
        }
    }
    
    private var verticalHeaderItem: some View {
        VStack(
            alignment: .leading,
            spacing: headerSpacing
        ) {
            headerItemContent
        }
    }
    
    @ViewBuilder
    private var headerItemContent: some View {
        titleValue
        headerContent
    }
}

// MARK: - Title and value:

private extension LineChartView {
    private var titleValue: some View {
        titleValueContent
            .frame(
                maxWidth: .infinity,
                alignment: .topLeading
            )
            .accessibilityElement(children: .combine)
    }
    
    private var titleValueContent: some View {
        VStack(
            alignment: titleValueAlignment,
            spacing: titleValueSpacing
        ) {
            titleValueItem
        }
    }
    
    @ViewBuilder
    private var titleValueItem: some View {
        titleContent
        valueContent
    }
    
    private var titleContent: some View {
        titleItem
            .font(titleFont)
            .textCase(titleTextCase)
            .multilineTextAlignment(titleAlignment)
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
            .multilineTextAlignment(valueAlignment)
            .foregroundStyle(valueColor)
    }
}

// MARK: - Chart:

private extension LineChartView {
    @ViewBuilder
    private var chart: some View {
        if isShowingChart {
            chartContent
        }
    }
    
    private var chartContent: some View {
        chartItem
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .padding(
                .horizontal,
                4
            )
            .frame(
                height: chartHeight,
                alignment: .center
            )
            .accessibilityElement(children: .combine)
    }
    
    private var chartItem: some View {
        Chart {
            chartLines
        }
    }
    
    private var chartLines: some ChartContent {
        ForEach(
            lines,
            content: line
        )
    }
    
    private func line(_ line: NT_ChartLine) -> some ChartContent {
        ForEach(values(line)) { value in
            lineValue(
                value,
                line
            )
        }
    }
    
    private func lineValue(
        _ value: NT_ChartLineValue,
        _ line: NT_ChartLine
    ) -> some ChartContent {
        lineValueContent(
            value,
            line
        )
        .foregroundStyle(
            by: .value(
                title(line),
                identifier(line)
            )
        )
        .interpolationMethod(.catmullRom)
        .lineStyle(lineStyle)
        .symbol() {
            lineValueSymbol(line)
        }
        .accessibilityValue(accessibilityValue(value))
    }
    
    @ChartContentBuilder
    private func lineValueContent(
        _ value: NT_ChartLineValue,
        _ line: NT_ChartLine
    ) -> some ChartContent {
        if isLineColorGradient {
            gradientLineValueItem(
                value,
                line
            )
        } else {
            colorLineValueItem(
                value,
                line
            )
        }
    }
    
    private func gradientLineValueItem(
        _ value: NT_ChartLineValue,
        _ line: NT_ChartLine
    ) -> some ChartContent {
        lineValueItem(
            value,
            line
        )
        .foregroundStyle(gradient(line))
    }
    
    private func colorLineValueItem(
        _ value: NT_ChartLineValue,
        _ line: NT_ChartLine
    ) -> some ChartContent {
        lineValueItem(
            value,
            line
        )
        .foregroundStyle(color(line))
    }
    
    private func lineValueItem(
        _ value: NT_ChartLineValue,
        _ line: NT_ChartLine
    ) -> some ChartContent {
        LineMark(
            x: .value(
                xAxisTitle,
                date(value)
            ),
            y: .value(
                yAxisTitle,
                self.value(value)
            )
        )
    }
    
    @ViewBuilder
    private func lineValueSymbol(_ line: NT_ChartLine) -> some View {
        if isShowingLineValueSymbol {
            lineValueSymbolContent(line)
        }
    }
    
    private func lineValueSymbolContent(_ line: NT_ChartLine) -> some View {
        RoundedRectangle(
            cornerRadius: lineValueSymbolCornerRadius,
            style: lineValueSymbolCornerStyle
        )
        .fill(backgroundColor)
        .frame(
            width: lineValueSymbolFrame,
            height: lineValueSymbolFrame,
            alignment: .center
        )
        .overlay(lineValueSymbolBorder(line))
    }
    
    private func lineValueSymbolBorder(_ line: NT_ChartLine) -> some View {
        RoundedRectangle(
            cornerRadius: lineValueSymbolCornerRadius,
            style: lineValueSymbolCornerStyle
        )
        .gradientBorder(
            width: lineValueSymbolBorderWidth,
            color: color(line),
            gradientStart: gradientStart(line),
            gradientEnd: gradientEnd(line),
            isGradient: isLineColorGradient
        )
    }
}

// MARK: - Legend:

private extension LineChartView {
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
            lines,
            content: legendItem
        )
    }
    
    private func legendItem(_ sector: NT_ChartLine) -> some View {
        IconBackgroundTitleSubtitleView(
            icon: legendItemIcon,
            iconSymbolVariant: legendItemIconSymbolVariant,
            iconColor: color(sector),
            iconGradientStart: gradientStart(sector),
            iconGradientEnd: gradientEnd(sector),
            isIconColorGradient: isLineColorGradient,
            isShowingIconBackground: false,
            iconSize: legendItemIconSize,
            title: title(sector),
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

private extension LineChartView {
    
    // MARK: - Private functions:
    
    /// Returns an array of the values for the given sector of the chart:
    private func values(_ sector: NT_ChartLine) -> [NT_ChartLineValue] {
        sector.values
    }
    
    /// Returns the identifier of the given line of the chart:
    private func identifier(_ line: NT_ChartLine) -> String {
        line.id
    }
    
    /// Returns the title of the given line of the chart:
    private func title(_ line: NT_ChartLine) -> String {
        line.title
    }
    
    /// Returns the accessibility value for the given value of the line of the chart that is needed for the VoiceOver:
    private func accessibilityValue(_ value: NT_ChartLineValue) -> String {
        
        /// Firstly getting the value of the given sector of the chart:
        let value: Double = value.value
        
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
    
    /// Returns the color for the given line of the chart:
    private func color(_ line: NT_ChartLine) -> Color {
        line.color
    }
    
    /// Returns the starting color of the gradient for the given line of the chart:
    private func gradientStart(_ line: NT_ChartLine) -> Color {
        line.gradientStart
    }
    
    /// Returns the ending color of the gradient for the given line of the chart:
    private func gradientEnd(_ line: NT_ChartLine) -> Color {
        line.gradientEnd
    }
    
    /// Returns the gradient for the given line of the chart:
    private func gradient(_ line: NT_ChartLine) -> LinearGradient {
        .init(
            colors: [
                gradientStart(line),
                gradientEnd(line)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    /// Returns an actual value of the given value of the line of the chart:
    private func value(_ value: NT_ChartLineValue) -> Double {
        value.value
    }
    
    /// Returns the date of the given value of the line of the chart:
    private func date(_ value: NT_ChartLineValue) -> Date {
        value.date
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        LineChartView(
            isShowingHeader: true,
            title: "Title",
            isTitleLocalized: true,
            titleFont: .footnote.weight(.bold),
            titleTextCase: .uppercase,
            titleAlignment: .leading,
            titleColor: .accent,
            valueFont: .title2.bold(),
            valueAlignment: .leading,
            valueColor: .primary,
            valueType: .currency(code: "USD"),
            totalValueType: .allValues,
            titleValueAlignment: .leading,
            titleValueSpacing: 4,
            headerAlignment: .top,
            headerSpacing: 12,
            lines: NT_ChartLine.example,
            xAxisTitle: "Date",
            yAxisTitle: "Amount",
            lineStyle: .init(
                lineWidth: 2,
                lineCap: .round,
                lineJoin: .round
            ),
            isShowingLineValueSymbol: true,
            lineValueSymbolCornerRadius: 8,
            lineValueSymbolCornerStyle: .continuous,
            lineValueSymbolFrame: 8,
            lineValueSymbolBorderWidth: 2,
            isLineColorGradient: true,
            chartHeight: 200,
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
        ) {
            
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
