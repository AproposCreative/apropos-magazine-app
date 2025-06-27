//
//  BarChartTitleSubtitleValueView.swift
//  Native
//

import SwiftUI
import Charts

struct BarChartTitleSubtitleValueView: View {
    
    // MARK: - Private properties:
    
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
    
    /// Maximum width of the title:
    private let titleMaxWidth: CGFloat?
    
    /// Alignment of the title if it has a maximum width applied to it:
    private let titleMaxWidthAlignment: Alignment
    
    /// 'Bool' value indicating whether or not the value should be shown at all:
    private let isShowingValue: Bool
    
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
    
    /// Type of the value of the chart:
    private let valueType: NT_ChartValueType
    
    /// Alignment of the title and the value:
    private let titleValueAlignment: VerticalAlignment
    
    /// Spacing between the title and the value:
    private let titleValueSpacing: Double
    
    /// 'Bool' value indicating whether or not the subtitle should be shown at all:
    private let isShowingSubtitle: Bool
    
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
    private let subtitleColor: Color
    
    /// Starting color of the gradient of the subtitle if applicable:
    private let subtitleGradientStart: Color
    
    /// Ending color of the gradient of the subtitle if applicable:
    private let subtitleGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the subtitle should have a gradient applied to it:
    private let isSubtitleColorGradient: Bool
    
    /// Alignment of the content of the title, value, and the subtitle:
    private let titleValueSubtitleAlignment: HorizontalAlignment
    
    /// Spacing between the content of the title, value, and the subtitle:
    private let titleValueSubtitleSpacing: Double
    
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
    
    init(
        isShowingTitle: Bool = true,
        title: String,
        isTitleLocalized: Bool = true,
        titleFont: Font = .title2.bold(),
        titleTextCase: Text.Case? = .none,
        titleAlignment: TextAlignment = .leading,
        titleLineSpacing: Double = 0,
        titleColor: Color = .primary,
        titleGradientStart: Color = .blueGradientStart,
        titleGradientEnd: Color = .blueGradientEnd,
        isTitleColorGradient: Bool = false,
        titleMaxWidth: CGFloat? = .infinity,
        titleMaxWidthAlignment: Alignment = .leading,
        isShowingValue: Bool = true,
        isValueLocalized: Bool = true,
        valueFont: Font = .title2.bold(),
        valueTextCase: Text.Case? = .none,
        valueAlignment: TextAlignment = .trailing,
        valueLineSpacing: Double = 0,
        valueColor: Color = .primary,
        valueGradientStart: Color = .blueGradientStart,
        valueGradientEnd: Color = .blueGradientEnd,
        isValueColorGradient: Bool = false,
        valueType: NT_ChartValueType = .number,
        titleValueAlignment: VerticalAlignment = .top,
        titleValueSpacing: Double = 12,
        isShowingSubtitle: Bool = true,
        subtitle: String,
        isSubtitleLocalized: Bool = true,
        subtitleFont: Font = .body,
        subtitleTextCase: Text.Case? = .none,
        subtitleAlignment: TextAlignment = .leading,
        subtitleLineSpacing: Double = 0,
        subtitleColor: Color = .secondary,
        subtitleGradientStart: Color = .blueGradientStart,
        subtitleGradientEnd: Color = .blueGradientEnd,
        isSubtitleColorGradient: Bool = false,
        titleValueSubtitleAlignment: HorizontalAlignment = .leading,
        titleValueSubtitleSpacing: Double = 6,
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
        cornerStyle: RoundedCornerStyle = .continuous
    ) {
        
        /// Properties initialization:
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
        self.titleMaxWidth = titleMaxWidth
        self.titleMaxWidthAlignment = titleMaxWidthAlignment
        self.isShowingValue = isShowingValue
        self.isValueLocalized = isValueLocalized
        self.valueFont = valueFont
        self.valueTextCase = valueTextCase
        self.valueAlignment = valueAlignment
        self.valueLineSpacing = valueLineSpacing
        self.valueColor = valueColor
        self.valueGradientStart = valueGradientStart
        self.valueGradientEnd = valueGradientEnd
        self.isValueColorGradient = isValueColorGradient
        self.valueType = valueType
        self.titleValueAlignment = titleValueAlignment
        self.titleValueSpacing = titleValueSpacing
        self.isShowingSubtitle = isShowingSubtitle
        self.subtitle = subtitle
        self.isSubtitleLocalized = isSubtitleLocalized
        self.subtitleFont = subtitleFont
        self.subtitleTextCase = subtitleTextCase
        self.subtitleAlignment = subtitleAlignment
        self.subtitleLineSpacing = subtitleLineSpacing
        self.subtitleColor = subtitleColor
        self.subtitleGradientStart = subtitleGradientStart
        self.subtitleGradientEnd = subtitleGradientEnd
        self.isSubtitleColorGradient = isSubtitleColorGradient
        self.titleValueSubtitleAlignment = titleValueSubtitleAlignment
        self.titleValueSubtitleSpacing = titleValueSubtitleSpacing
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
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be shown at all:
    private var isShowing: Bool {
        isShowingHeader
        || isShowingChart
    }
    
    /// 'Bool' value indicating whether or not the header should be shown at all:
    private var isShowingHeader: Bool {
        isShowingTitle
        || isShowingSubtitle
        || isShowingValue
    }
    
    /// 'Bool' value indicating whether or not the chart should be shown at all:
    private var isShowingChart: Bool {
        !bars.isEmpty
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

private extension BarChartTitleSubtitleValueView {
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

private extension BarChartTitleSubtitleValueView {
    @ViewBuilder
    private var header: some View {
        if isShowingHeader {
            headerContent
        }
    }
    
    private var headerContent: some View {
        TitleSubtitleValueView(
            isShowingTitle: isShowingTitle,
            title: title,
            isTitleLocalized: isTitleLocalized,
            titleFont: titleFont,
            titleTextCase: titleTextCase,
            titleAlignment: titleAlignment,
            titleLineSpacing: titleLineSpacing,
            titleColor: titleColor,
            titleGradientStart: titleGradientStart,
            titleGradientEnd: titleGradientEnd,
            isTitleColorGradient: isTitleColorGradient,
            titleMaxWidth: titleMaxWidth,
            titleMaxWidthAlignment: titleMaxWidthAlignment,
            isShowingValue: isShowingValue,
            value: value,
            isValueLocalized: isValueLocalized,
            valueFont: valueFont,
            valueTextCase: valueTextCase,
            valueAlignment: valueAlignment,
            valueLineSpacing: valueLineSpacing,
            valueColor: valueColor,
            valueGradientStart: valueGradientStart,
            valueGradientEnd: valueGradientEnd,
            isValueColorGradient: isValueColorGradient,
            titleValueAlignment: titleValueAlignment,
            titleValueSpacing: titleValueSpacing,
            isShowingSubtitle: isShowingSubtitle,
            subtitle: subtitle,
            isSubtitleLocalized: isSubtitleLocalized,
            subtitleFont: subtitleFont,
            subtitleTextCase: subtitleTextCase,
            subtitleAlignment: subtitleAlignment,
            subtitleLineSpacing: subtitleLineSpacing,
            subtitleColor: subtitleColor,
            subtitleGradientStart: subtitleGradientStart,
            subtitleGradientEnd: subtitleGradientEnd,
            isSubtitleColorGradient: isSubtitleColorGradient,
            alignment: titleValueSubtitleAlignment,
            spacing: titleValueSubtitleSpacing,
            verticalPadding: 0,
            horizontalPadding: 0,
            isShowingBackground: false,
            cornerRadius: 0
        )
    }
}

// MARK: - Chart:

private extension BarChartTitleSubtitleValueView {
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

private extension BarChartTitleSubtitleValueView {
    
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
        BarChartTitleSubtitleValueView(
            isShowingTitle: true,
            title: "Title",
            isTitleLocalized: true,
            titleFont: .title2.bold(),
            titleTextCase: .none,
            titleAlignment: .leading,
            titleLineSpacing: 0,
            titleColor: .primary,
            titleGradientStart: .blueGradientStart,
            titleGradientEnd: .blueGradientEnd,
            isTitleColorGradient: false,
            titleMaxWidth: .infinity,
            titleMaxWidthAlignment: .leading,
            isShowingValue: true,
            isValueLocalized: true,
            valueFont: .title2.bold(),
            valueTextCase: .none,
            valueAlignment: .trailing,
            valueLineSpacing: 0,
            valueColor: .primary,
            valueGradientStart: .blueGradientStart,
            valueGradientEnd: .blueGradientEnd,
            isValueColorGradient: false,
            valueType: .number,
            titleValueAlignment: .top,
            titleValueSpacing: 12,
            isShowingSubtitle: true,
            subtitle: "Subtitle",
            isSubtitleLocalized: true,
            subtitleFont: .body,
            subtitleTextCase: .none,
            subtitleAlignment: .leading,
            subtitleLineSpacing: 0,
            subtitleColor: .secondary,
            subtitleGradientStart: .blueGradientStart,
            subtitleGradientEnd: .blueGradientEnd,
            isSubtitleColorGradient: false,
            titleValueSubtitleAlignment: .leading,
            titleValueSubtitleSpacing: 6,
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
