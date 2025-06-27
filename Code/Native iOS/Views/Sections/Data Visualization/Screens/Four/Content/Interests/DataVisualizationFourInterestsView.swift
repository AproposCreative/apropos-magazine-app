//
//  DataVisualizationFourInterestsView.swift
//  Native
//

import SwiftUI

struct DataVisualizationFourInterestsView: View {
    
    // MARK: - Properties:
    
    /// An array of the interests to display:
    let interests: [NT_Interest]
    
    // MARK: - Private properties:
    
    /// Type of the interests that is currently selected:
    @State private var interestType: NT_InterestType = .all
    
    init(interests: [NT_Interest]) {
        
        /// Properties initialization:
        self.interests = interests
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    @ViewBuilder
    private var content: some View {
        if isShowing {
            item
        }
    }
    
    private var mainContent: some View {
        item
            .onChange(
                of: interestType,
                interestTypeOnChange
            )
    }
}

// MARK: - Item:

private extension DataVisualizationFourInterestsView {
    private var item: some View {
        VStack(
            alignment: .leading,
            spacing: 16
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

// MARK: - Header

private extension DataVisualizationFourInterestsView {
    private var header: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            headerContent
        }
    }
    
    @ViewBuilder
    private var headerContent: some View {
        headerItem
        typePicker
    }
    
    private var headerItem: some View {
        SectionHeaderView(
            title: "Followers by Interest",
            isShowingSubtitle: true,
            subtitle: "Based on the available data"
        )
    }
}

// MARK: - Type picker:

private extension DataVisualizationFourInterestsView {
    private var typePicker: some View {
        typePickerContent
            .pickerStyle(.segmented)
            .labelsHidden()
    }
    
    private var typePickerContent: some View {
        Picker(
            "Types",
            selection: $interestType
        ) {
            typesContent
        }
    }
    
    private var typesContent: some View {
        ForEach(
            types,
            content: type
        )
    }
    
    private func type(_ type: NT_InterestType) -> some View {
        Text(title(type))
            .tag(type)
    }
}

// MARK: - Chart

private extension DataVisualizationFourInterestsView {
    private var chart: some View {
        PieChartView(
            isShowingTitleValue: false,
            sectors: sectors,
            legendItemBackgroundColor: .init(.systemBackground),
            backgroundColor: .init(.secondarySystemBackground)
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        DataVisualizationFourInterestsView(interests: NT_Interest.example)
    }
    .safeAreaPadding(
        .all,
        16
    )
    .safeAreaPadding(
        .bottom,
        16
    )
    .localizedNavigationTitle(title: "Analytics")
    .navigationStack()
}
