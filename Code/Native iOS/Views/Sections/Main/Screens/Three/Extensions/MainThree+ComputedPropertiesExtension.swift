//
//  MainThree+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension MainThreeView {
    
    // MARK: - Computed properties:
    
    /// An array of the messages that are filtered by the search text that is inputed by the user:
    var searchMessages: [NT_Message] {
        messages.filter {
            isSearchTextEmpty
                ? true
                : $0.content.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    /// An array of the groups with the messages that are filtered by the search text that is inputed by the user:
    var searchGroups: [NT_MessagesGroup] {
        groups.filter {
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
            !searchMessages.isEmpty
            || !searchGroups.isEmpty
        ) ? 0 : 1
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the text to search the messages and the groups with the messages by that is inputed the user is empty:
    private var isSearchTextEmpty: Bool {
        searchText.isEmpty
    }
}
