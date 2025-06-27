//
//  OnboardingFiveView.swift
//  Native
//

import SwiftUI

struct OnboardingFiveView: View {
    
    // MARK: - Properties:
    
    /// Dismisses the view:
    @Environment(\.dismiss) var dismiss
    
    /// Group of the features that is currently shown:
    @State var currentGroup: NT_FeatureGroup? = .first
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .background(Color(.systemGroupedBackground))
            .animation(
                .default,
                value: currentGroup
            )
            .navigationStack()
    }
}

// MARK: - Item:

private extension OnboardingFiveView {
    private var item: some View {
        VStack(
            alignment: .center,
            spacing: 0
        ) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        scroll
        toolbar
    }
}

// MARK: - Scroll:

private extension OnboardingFiveView {
    private var scroll: some View {
        ScrollView {
            groupsScroll
        }
    }
}

// MARK: - Groups scroll:

private extension OnboardingFiveView {
    private var groupsScroll: some View {
        groupsScrollContent
            .scrollIndicators(.hidden)
            .safeAreaPadding(
                .top,
                48
            )
            .safeAreaPadding(
                .horizontal,
                16
            )
            .safeAreaPadding(
                .bottom,
                32
            )
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $currentGroup)
    }
    
    private var groupsScrollContent: some View {
        ScrollView(.horizontal) {
            groupsScrollItem
        }
    }
    
    private var groupsScrollItem: some View {
        groupsContent
            .scrollTargetLayout()
    }
}

// MARK: - Groups:

private extension OnboardingFiveView {
    private var groupsContent: some View {
        HStack(
            alignment: .top,
            spacing: 32
        ) {
            groupsItem
        }
    }
    
    private var groupsItem: some View {
        ForEach(
            groups,
            content: group
        )
    }
    
    private func group(_ group: NT_FeatureGroup) -> some View {
        groupContent(group)
            .scrollContentBackground(.hidden)
            .containerRelativeFrame(.horizontal)
            .scrollTransition(axis: .horizontal) { content, phase in
                content
                    .scaleEffect(scaleEffect(inPhase: phase))
            }
            .id(group)
    }
    
    private func groupContent(_ group: NT_FeatureGroup) -> some View {
        VStack(
            alignment: .center,
            spacing: 48
        ) {
            groupItem(group)
        }
    }
    
    @ViewBuilder
    private func groupItem(_ group: NT_FeatureGroup) -> some View {
        groupTitleContent(group)
        featuresContent(group)
    }
    
    private func groupTitleContent(_ group: NT_FeatureGroup) -> some View {
        groupTitle(group)
            .font(.largeTitle.bold())
            .multilineTextAlignment(.center)
            .foregroundStyle(.primary)
    }
    
    private func featuresContent(_ group: NT_FeatureGroup) -> some View {
        LazyVStack(
            alignment: .leading,
            spacing: 16
        ) {
            featuresItem(group)
        }
    }
    
    private func featuresItem(_ group: NT_FeatureGroup) -> some View {
        ForEach(
            features(group),
            content: feature
        )
    }
    
    private func feature(_ feature: NT_Feature) -> some View {
        IconBackgroundTitleSubtitleView(
            icon: icon(feature),
            isIconColorGradient: true,
            isShowingIconBackground: false,
            title: title(feature),
            subtitle: subtitle(feature)
        )
    }
}

// MARK: - Toolbar:

private extension OnboardingFiveView {
    private var toolbar: some View {
        BottomToolbarView(horizontalAlignment: .center) {
            toolbarContent
        }
    }
    
    @ViewBuilder
    private var toolbarContent: some View {
        pagination
        getStartedButton
    }
    
    private var pagination: some View {
        PaginationView(
            current: $currentGroup,
            all: groups
        )
    }
    
    private var getStartedButton: some View {
        ButtonView(
            title: "Get Started",
            action: getStarted
        )
    }
}

// MARK: - Preview:

#Preview {
    OnboardingFiveView()
}
