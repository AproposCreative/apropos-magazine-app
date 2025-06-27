//
//  MainTwoContentView.swift
//  Native
//

import SwiftUI

struct MainTwoContentView: View {
    
    // MARK: - Properties:
    
    /// An array of the 'Just or You' courses to display:
    @State var justForYouCourses: [NT_Course] = []
    
    /// An array of the popular categories to display:
    @State var popularCategories: [NT_CoursesCategory] = []
    
    /// An array of the user's courses to display:
    @State var myCourses: [NT_Course] = []
    
    /// 'Bool' value indicating whether or not the data is currently being fetched:
    @State var isFetching: Bool = true
    
    /// Text to search the courses and the categories by that is inputed by the user:
    @State var searchText: String = ""
    
    // MARK: - Private properties:
    
    /// 'Just for You' course that is currently shown:
    @State private var currentJustForYouCourse: NT_Course? = NT_Course.example.first
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        list
            .overlay {
                loading
            }
            .overlay {
                nothingHere
            }
            .localizedNavigationTitle(title: "Courses")
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer
            )
            .toolbarAvatar()
            .navigationDestination(
                for: NT_CoursesCategory.self,
                destination: category
            )
            .animation(
                .default,
                value: searchJustForYouCourses
            )
            .animation(
                .default,
                value: searchPopularCategories
            )
            .animation(
                .default,
                value: searchMyCourses
            )
            .animation(
                .default,
                value: isFetching
            )
            .animation(
                .default,
                value: currentJustForYouCourse
            )
            .task {
                await fetchData()
            }
            .navigationStack()
    }
}

// MARK: - Empty states:

private extension MainTwoContentView {
    private var loading: some View {
        loadingContent
            .opacity(loadingOpacity)
    }
    
    private var loadingContent: some View {
        LoadingView(
            isShowing: true,
            color: .secondary,
            scale: 1.5
        )
    }
    
    private var nothingHere: some View {
        nothingHereContent
            .opacity(nothingHereOpacity)
    }
    
    private var nothingHereContent: some View {
        EmptyStateView(
            title: "Nothing Here",
            subtitle: "We don't have anything to display here."
        )
    }
}

// MARK: - List:

private extension MainTwoContentView {
    private var list: some View {
        listContent
            .listStyle(.plain)
    }
    
    private var listContent: some View {
        List {
            listItem
        }
    }
    
    @ViewBuilder
    private var listItem: some View {
        justForYou
        MainTwoPopularCategoriesView(categories: searchPopularCategories)
        MainTwoMyCoursesView(courses: searchMyCourses)
    }
}

// MARK: - Just for you:

private extension MainTwoContentView {
    private var justForYou: some View {
        MainTwoJustForYouView(
            courses: searchJustForYouCourses,
            currentCourse: $currentJustForYouCourse
        )
    }
}

// MARK: - Category:

private extension MainTwoContentView {    
    private func category(_ category: NT_CoursesCategory) -> some View {
        PlaceholderView(title: title(category))
    }
}

// MARK: - Preview:

#Preview {
    MainTwoContentView()
}
