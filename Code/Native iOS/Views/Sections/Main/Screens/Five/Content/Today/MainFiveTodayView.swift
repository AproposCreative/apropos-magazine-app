//
//  MainFiveTodayView.swift
//  Native
//

import SwiftUI

struct MainFiveTodayView: View {
    
    // MARK: - Properties:
    
    /// An array of the tasks to display:
    let tasks: [NT_Task]
    
    init(tasks: [NT_Task]) {
        
        /// Properties initialization:
        self.tasks = tasks
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

private extension MainFiveTodayView {
    private var item: some View {
        Section("Today") {
            tasksContent
        }
    }
}

// MARK: - Tasks:

private extension MainFiveTodayView {
    private var tasksContent: some View {
        ForEach(
            tasks,
            content: task
        )
    }
    
    private func task(_ task: NT_Task) -> some View {
        SelectButtonTitleSubtitleBadgesView(
            selectButtonFrame: 24,
            isSelected: isCompleted(task),
            title: title(task),
            subtitle: notes(task),
            badges: tagBadges(task),
            verticalPadding: 0,
            horizontalPadding: 0,
            isShowingBackground: false,
            cornerRadius: 0,
            selectButtonAction: markAsCompleted
        )
    }
}

// MARK: - Preview:

#Preview {
    List {
        MainFiveTodayView(tasks: NT_Task.example)
    }
    .listStyle(.insetGrouped)
    .localizedNavigationTitle(title: "Overview")
    .navigationStack()
}
