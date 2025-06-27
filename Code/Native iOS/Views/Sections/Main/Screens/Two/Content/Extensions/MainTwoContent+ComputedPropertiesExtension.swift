//
//  MainTwoContent+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension MainTwoContentView {
    
    // MARK: - Computed properties:
    
    /// An array of the 'Just for You' courses that are filtered by the search text that is inputed by the user:
    var searchJustForYouCourses: [NT_Course] {
        justForYouCourses.filter {
            isSearchTextEmpty
                ? true
                : $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    /// An array of the popular categories that are filtered by the search text that is inputed by the user:
    var searchPopularCategories: [NT_CoursesCategory] {
        popularCategories.filter {
            isSearchTextEmpty
                ? true
                : $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    /// An array of the user's courses that are filtered by the search text that is inputed by the user:
    var searchMyCourses: [NT_Course] {
        myCourses.filter {
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
            !searchJustForYouCourses.isEmpty
            || !searchPopularCategories.isEmpty
            || !searchMyCourses.isEmpty
        ) ? 0 : 1
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the text to search the courses and the categories by that is inputed the user is empty:
    private var isSearchTextEmpty: Bool {
        searchText.isEmpty
    }
}
