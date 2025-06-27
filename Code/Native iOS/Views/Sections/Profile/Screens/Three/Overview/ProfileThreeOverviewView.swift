//
//  ProfileThreeOverviewView.swift
//  Native
//

import SwiftUI

struct ProfileThreeOverviewView: View {
    
    // MARK: - Properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .headerProminence(.increased)
    }
}

// MARK: - Item:

private extension ProfileThreeOverviewView {
    private var item: some View {
        Section("Overview") {
            statsContent
        }
    }
}

// MARK: - Stats:

private extension ProfileThreeOverviewView {
    private var statsContent: some View {
        statsItem
            .padding(
                .vertical,
                2
            )
    }
    
    private var statsItem: some View {
        LazyVGrid(
            columns: columns,
            alignment: .leading,
            spacing: spacing
        ) {
            statsItemContent
        }
    }
    
    private var statsItemContent: some View {
        ForEach(
            stats,
            content: stat
        )
    }
    
    private func stat(_ stat: NT_ProfileTaskStat) -> some View {
        TitleSubtitleView(
            title: value(stat),
            subtitle: title(stat)
        )
    }
}

// MARK: - Preview:

#Preview {
    List {
        ProfileThreeOverviewView()
    }
    .listStyle(.insetGrouped)
    .localizedNavigationTitle(title: "Profile")
    .navigationStack()
}
