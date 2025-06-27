//
//  MainFiveProjects+FunctionsExtension.swift
//  Native
//

import SwiftUI

extension MainFiveProjectsView {
    
    // MARK: - Functions:
    
    /// Returns the title of the given project:
    func title(_ project: NT_Project) -> String {
        project.title
    }
    
    /// Returns the count of the tasks that are part of the given project as a string:
    func tasksCount(_ project: NT_Project) -> String {
        "\(project.tasksCount) tasks"
    }
    
    /// Returns the color of the given project:
    func color(_ project: NT_Project) -> Color {
        .init(project.color)
    }
    
    /// Returns the starting color of the gradient of the given project:
    func gradientStart(_ project: NT_Project) -> Color {
        .init(project.gradientStart)
    }
    
    /// Returns the ending color of the gradient of the given project:
    func gradientEnd(_ project: NT_Project) -> Color {
        .init(project.gradientEnd)
    }
    
    /// Returns the icon of the given project:
    func icon(_ project: NT_Project) -> String {
        project.icon
    }
}
