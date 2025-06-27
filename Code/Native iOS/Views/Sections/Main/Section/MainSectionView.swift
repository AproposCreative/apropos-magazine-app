//
//  MainSectionView.swift
//  Native
//

import SwiftUI

struct MainSectionView: View {
    
    // MARK: - Properties:
    
    /// Screen that is currently shown (Can be 'nil' or no screen at all):
    @State var currentScreen: NT_MainScreen? = nil
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        list
            .navigationTitle("Main")
            .sheet(
                item: $currentScreen,
                content: showScreen
            )
    }
}

// MARK: - List:

private extension MainSectionView {
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

private extension MainSectionView {
    private var screensContent: some View {
        ForEach(
            screens,
            content: screen
        )
    }
    
    private func screen(_ screen: NT_MainScreen) -> some View {
        MainSectionRowView(
            screen: screen,
            viewAction: view
        )
    }
}

// MARK: - Screen:

private extension MainSectionView {
    @ViewBuilder
    private func showScreen(_ screen: NT_MainScreen) -> some View {
        switch screen {
        case .first: MainOneView()
        case .second: MainTwoView()
        case .third: MainThreeView()
        case .fourth: MainFourView()
        case .fifth: MainFiveView()
        case .sixth: MainSixView()
        case .seventh: MainSevenView()
        case .eighth: MainEightView()
        case .ninth: MainNineView()
        case .tenth: MainTenView()
        }
    }
}

// MARK: - Preview:

#Preview {
    MainSectionView()
}
