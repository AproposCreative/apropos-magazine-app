//
//  MainFiveContent+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension MainFiveContentView {
    
    // MARK: - Computed properties:
    
    /// An array of the tasks that are filtered by the search text that is inputed by the user:
    var searchTasks: [NT_Task] {
        tasks.filter {
            isSearchTextEmpty
                ? true
                : $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    /// An array of the comments that are filtered by the search text that is inputed by the user:
    var searchComments: [NT_Comment] {
        comments.filter {
            isSearchTextEmpty
                ? true
                : $0.content.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    /// An array of the projects that are filtered by the search text that is inputed by the user:
    var searchProjects: [NT_Project] {
        projects.filter {
            isSearchTextEmpty
                ? true
                : $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    /// Opacity of the loading indicator:
    var loadingOpacity: Double {
        isFetching ? 1 : 0
    }
    
    /// Opacity of the 'Nothing Here' overlay:
    var nothingHereOpacity: Double {
        isFetching || (
            !searchTasks.isEmpty
            || !searchComments.isEmpty
            || !searchProjects.isEmpty
        ) ? 0 : 1
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the text to search the tasks, comments, and the projects by that is inputed the user is empty:
    private var isSearchTextEmpty: Bool {
        searchText.isEmpty
    }
}
