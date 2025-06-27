//
//  MainFiveProjectsView.swift
//  Native
//

import SwiftUI

struct MainFiveProjectsView: View {
    
    // MARK: - Properties:
    
    /// An array of the projects to display:
    let projects: [NT_Project]
    
    init(projects: [NT_Project]) {
        
        /// Properties initialization:
        self.projects = projects
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
            .headerProminence(.increased)
    }
}

// MARK: - Item:

private extension MainFiveProjectsView {
    private var item: some View {
        Section("Projects") {
            projectsContent
        }
    }
}

// MARK: - Projects:

private extension MainFiveProjectsView {
    private var projectsContent: some View {
        ForEach(
            projects,
            content: project
        )
    }
    
    private func project(_ project: NT_Project) -> some View {
        NavigationLink(value: project) {
            projectLabel(project)
        }
    }
    
    private func projectLabel(_ project: NT_Project) -> some View {
        IconBackgroundTitleSubtitleView(
            icon: icon(project),
            iconBackgroundGradientStart: gradientStart(project),
            iconBackgroundGradientEnd: gradientEnd(project),
            title: title(project),
            subtitle: tasksCount(project),
            verticalPadding: 4,
            horizontalPadding: 0,
            isShowingBackground: false,
            cornerRadius: 0
        )
    }
}

// MARK: - Preview:

#Preview {
    List {
        MainFiveProjectsView(projects: NT_Project.example)
    }
    .listStyle(.insetGrouped)
    .localizedNavigationTitle(title: "Overview")
    .navigationDestination(for: NT_Project.self) { project in
        PlaceholderView(title: project.title)
    }
    .navigationStack()
}
