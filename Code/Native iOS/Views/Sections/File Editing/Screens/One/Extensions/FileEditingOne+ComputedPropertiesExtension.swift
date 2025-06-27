//
//  FileEditingOne+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension FileEditingOneView {
    
    // MARK: - Computed properties:
    
    /// An array of the sections that are filtered by the search text that is inputed by the user:
    var searchSections: [NT_DesignToolSection] {
        sections.filter {
            isSearchTextEmpty
                ? true
                : $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    /// An array of the folders that are filtered by the search text that is inputed by the user:
    var searchFolders: [NT_DesignToolFolder] {
        folders.filter {
            isSearchTextEmpty
                ? true
                : $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    /// An array of the tags that are filtered by the search text that is inputed by the user:
    var searchTags: [NT_DesignToolTag] {
        tags.filter {
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
            || !searchSections.isEmpty
            || !searchFolders.isEmpty
            || !searchTags.isEmpty
        ) ? 0 : 1
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the text to search the sections, tags, and folders by that is inputed the user is empty:
    private var isSearchTextEmpty: Bool {
        searchText.isEmpty
    }
}
