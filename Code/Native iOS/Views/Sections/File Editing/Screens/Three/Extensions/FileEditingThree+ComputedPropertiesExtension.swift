//
//  FileEditingThree+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension FileEditingThreeView {
    
    // MARK: - Computed properties:
    
    /// An array of the sections that are filtered by the search text that is inputed by the user:
    var searchSections: [ NT_WhiteboardSection] {
        sections.filter {
            isSearchTextEmpty
                ? true
                : $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    /// An array of the boards of the user that are filtered by the search text that is inputed by the user:
    var searchUserBoards: [ NT_WhiteboardBoard] {
        userBoards.filter {
            isSearchTextEmpty
                ? true
                : $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    /// An array of the boards of the team that are filtered by the search text that is inputed by the user:
    var searchTeamBoards: [ NT_WhiteboardBoard] {
        teamBoards.filter {
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
        (
            isFetching
            || !sections.isEmpty
            || !userBoards.isEmpty
            || !teamBoards.isEmpty
        ) ? 0 : 1
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the text to search the sections and the boards by that is inputed the user is empty:
    private var isSearchTextEmpty: Bool {
        searchText.isEmpty
    }
}
