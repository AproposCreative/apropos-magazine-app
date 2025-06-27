//
//  PaywallEightComparisonView.swift
//  Native
//

import SwiftUI

struct PaywallEightComparisonView: View {
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        VStack(
            alignment: .leading,
            spacing: 16
        ) {
            item
        }
    }
}

// MARK: - Item:

private extension PaywallEightComparisonView {
    @ViewBuilder
    private var item: some View {
        SectionHeaderView(title: "Great Features You will Love")
        ComparisonView(rows: features)
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        PaywallEightComparisonView()
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
