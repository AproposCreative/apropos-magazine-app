//
//  PaywallSectionView.swift
//  Native
//

import SwiftUI

struct PaywallSectionView: View {
    
    // MARK: - Properties:
    
    /// Screen that is currently shown (Can be 'nil' or no screen at all):
    @State var currentScreen: NT_PaywallScreen? = nil
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        list
            .navigationTitle("Paywall")
            .sheet(
                item: $currentScreen,
                content: showScreen
            )
    }
}

// MARK: - List:

private extension PaywallSectionView {
    private var list: some View {
        listContent
            .listStyle(.insetGrouped)
    }
    
    private var listContent: some View {
        List {
            screensContent
        }
    }
}

// MARK: - Screens:

private extension PaywallSectionView {
    private var screensContent: some View {
        ForEach(
            screens,
            content: screen
        )
    }
    
    private func screen(_ screen: NT_PaywallScreen) -> some View {
        PaywallSectionRowView(
            screen: screen,
            viewAction: view
        )
    }
}

// MARK: - Screen:

private extension PaywallSectionView {
    @ViewBuilder
    private func showScreen(_ screen: NT_PaywallScreen) -> some View {
        switch screen {
        case .first: PaywallOneView()
        case .second: PaywallTwoView()
        case .third: PaywallThreeView()
        case .fourth: PaywallFourView()
        case .fifth: PaywallFiveView()
        case .sixth: PaywallSixView()
        case .seventh: PaywallSevenView()
        case .eighth: PaywallEightView()
        case .ninth: PaywallNineView()
        case .tenth: PaywallTenView()
        case .eleventh: PaywallElevenView()
        case .twelfth: PaywallTwelveView()
        case .thirteenth: PaywallThirteenView()
        case .fourteenth: PaywallFourteenView()
        case .fifteenth: PaywallFifteenView()
        }
    }
}

// MARK: - Preview:

#Preview {
    PaywallSectionView()
}
