//
//  OnboardingSectionView.swift
//  Native
//

import SwiftUI

struct OnboardingSectionView: View {
    
    // MARK: - Properties:
    
    /// Screen that is currently shown (Can be 'nil' or no screen at all):
    @State var currentScreen: NT_OnboardingScreen? = nil
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        list
            .navigationTitle("Onboarding")
            .sheet(
                item: $currentScreen,
                content: showScreen
            )
    }
}

// MARK: - List:

private extension OnboardingSectionView {
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

private extension OnboardingSectionView {
    private var screensContent: some View {
        ForEach(
            screens,
            content: screen
        )
    }
    
    private func screen(_ screen: NT_OnboardingScreen) -> some View {
        OnboardingSectionRowView(
            screen: screen,
            viewAction: view
        )
    }
}

// MARK: - Screen:

private extension OnboardingSectionView {
    @ViewBuilder
    private func showScreen(_ screen: NT_OnboardingScreen) -> some View {
        switch screen {
        case .first: OnboardingOneView()
        case .second: OnboardingTwoView()
        case .third: OnboardingThreeView()
        case .fourth: OnboardingFourView()
        case .fifth: OnboardingFiveView()
        case .sixth: OnboardingSixView()
        case .seventh: OnboardingSevenView()
        case .eighth: OnboardingEightView()
        case .ninth: OnboardingNineView()
        case .tenth: OnboardingTenView()
        case .eleventh: OnboardingElevenView()
        case .twelfth: OnboardingTwelveView()
        case .thirteenth: OnboardingThirteenView()
        case .fourteenth: OnboardingFourteenView()
        case .fifteenth: OnboardingFifteenView()
        }
    }
}

// MARK: - Preview:

#Preview {
    OnboardingSectionView()
}
