//
//  BarChartView.swift
//  Native
//

import SwiftUI
import Charts

struct BarChartView<HeaderContent: View>: View {
    
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
    
    /// Alignment of the title and the value of the chart:
    private let titleValueAlignment: HorizontalAlignment
    
    /// Spacing between the title and the value of the chart:
    private let titleValueSpacing: Double
    
    /// Alignment of the header of the chart:
    private let headerAlignment: VerticalAlignment
    
    /// Spacing between the content of the header of the chart:
    private let headerSpacing: Double
    
    /// An array of the bars of the chart to display:
    private let bars: [NT_ChartBar]
    
    /// Title of the bar of the chart:
    private let barTitle: LocalizedStringKey
    
    /// Width of the bars of the chart:
    private let barWidth: MarkDimension
    
    /// 'Bool' value indicating whether or not the colors of the background of the bars of the chart should have a gradient applied to them:
    private let isBarBackgroundGradient: Bool
    
    /// Radius of the rounded corners of the bars of the chart:
    private let barCornerRadius: Double
    
    /// Style of the rounded corners of the bars of the chart:
    private let barCornerStyle: RoundedCornerStyle
    
    /// Alignment of the chart:
    private let chartAlignment: NT_Alignment
    
    /// Height of the chart:
    private let chartHeight: Double
    
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
        titleValueAlignment: HorizontalAlignment = .leading,
        titleValueSpacing: Double = 4,
        headerAlignment: VerticalAlignment = .top,
        headerSpacing: Double = 12,
        bars: [NT_ChartBar],
        barTitle: LocalizedStringKey = "Title",
        barWidth: MarkDimension = 20,
        isBarBackgroundGradient: Bool = true,
        barCornerRadius: Double = 8,
        barCornerStyle: RoundedCornerStyle = .continuous,
        chartAlignment: NT_Alignment = .horizontal,
        chartHeight: Double = 200,
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
        self.titleValueAlignment = titleValueAlignment
        self.titleValueSpacing = titleValueSpacing
        self.headerAlignment = headerAlignment
        self.headerSpacing = headerSpacing
        self.bars = bars
        self.barTitle = barTitle
        self.barWidth = barWidth
        self.isBarBackgroundGradient = isBarBackgroundGradient
        self.barCornerRadius = barCornerRadius
        self.barCornerStyle = barCornerStyle
        self.chartAlignment = chartAlignment
        self.chartHeight = chartHeight
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
        !bars.isEmpty
    }
    
    /// 'Bool' value indicating whether or not the content of the view should be moved that is based on the size of the dynamic type that is currently selected:
    private var shouldMoveContent: Bool {
        dynamicTypeSize >= .accessibility1
    }
    
    /// Total value of all of the bars of the chart as a string:
    private var value: String {
        
        /// Firstly getting the value of all of the bars of the chart:
        let value: Double = bars.map { $0.value }.reduce(0, +)
        
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

private extension BarChartView {
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
    }
}

// MARK: - Header:

private extension BarChartView {
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

private extension BarChartView {
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

private extension BarChartView {
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
            .frame(
                height: chartHeight,
                alignment: .bottom
            )
            .accessibilityElement(children: .combine)
    }
    
    private var chartItem: some View {
        Chart {
            chartBarsContent
        }
    }
    
    private var chartBarsContent: some ChartContent {
        ForEach(
            bars,
            content: chartBar
        )
    }
    
    private func chartBar(_ bar: NT_ChartBar) -> some ChartContent {
        chartBarContent(bar)
            .clipShape(
                .rect(
                    cornerRadius: barCornerRadius,
                    style: barCornerStyle
                )
            )
            .accessibilityValue(accessibilityValue(bar))
    }
    
    @ChartContentBuilder
    private func chartBarContent(_ bar: NT_ChartBar) -> some ChartContent {
        if isBarBackgroundGradient {
            gradientChartBarItem(bar)
        } else {
            colorChartBarItem(bar)
        }
    }
    
    private func gradientChartBarItem(_ bar: NT_ChartBar) -> some ChartContent {
        chartBarItem(bar)
            .foregroundStyle(gradient(bar))
    }
    
    private func colorChartBarItem(_ bar: NT_ChartBar) -> some ChartContent {
        chartBarItem(bar)
            .foregroundStyle(color(bar))
    }
    
    @ChartContentBuilder
    private func chartBarItem(_ bar: NT_ChartBar) -> some ChartContent {
        switch chartAlignment {
        case .horizontal: horizontalChartBarItem(bar)
        case .vertical: verticalChartBarItem(bar)
        }
    }
    
    private func horizontalChartBarItem(_ bar: NT_ChartBar) -> some ChartContent {
        BarMark(
            x: .value(
                barTitle,
                title(bar)
            ),
            y: .value(
                valueTitle(bar),
                value(bar)
            ),
            width: barWidth
        )
    }
    
    private func verticalChartBarItem(_ bar: NT_ChartBar) -> some ChartContent {
        BarMark(
            x: .value(
                valueTitle(bar),
                value(bar)
            ),
            y: .value(
                barTitle,
                title(bar)
            ),
            width: barWidth
        )
    }
}

// MARK: - Functions:

private extension BarChartView {
    
    // MARK: - Private functions:
    
    /// Returns the title for the given bar of the chart:
    private func title(_ bar: NT_ChartBar) -> String {
        bar.title
    }
    
    /// Returns the title of the value for the given bar of the chart:
    private func valueTitle(_ bar: NT_ChartBar) -> String {
        bar.valueTitle
    }
    
    /// Returns the value for the given bar of the chart:
    private func value(_ bar: NT_ChartBar) -> Double {
        bar.value
    }
    
    /// Returns the accessibility value for the given bar of the chart that is needed for the VoiceOver:
    private func accessibilityValue(_ bar: NT_ChartBar) -> String {
        
        /// Firstly getting the value of the given bar of the chart:
        let value: Double = value(bar)
        
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
    
    /// Returns the color for the given bar of the chart:
    private func color(_ bar: NT_ChartBar) -> Color {
        bar.color
    }
    
    /// Returns the gradient for the given bar of the chart:
    private func gradient(_ bar: NT_ChartBar) -> LinearGradient {
        .init(
            colors: [
                bar.gradientStart,
                bar.gradientEnd
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        BarChartView(
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
            titleValueAlignment: .leading,
            titleValueSpacing: 4,
            headerAlignment: .top,
            headerSpacing: 12,
            bars: NT_ChartBar.example,
            barTitle: "Title",
            barWidth: 20,
            isBarBackgroundGradient: true,
            barCornerRadius: 8,
            barCornerStyle: .continuous,
            chartAlignment: .horizontal,
            chartHeight: 200,
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
