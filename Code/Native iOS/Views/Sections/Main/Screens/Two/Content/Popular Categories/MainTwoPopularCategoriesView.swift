//
//  MainTwoPopularCategoriesView.swift
//  Native
//

import SwiftUI

struct MainTwoPopularCategoriesView: View {
    
    // MARK: - Properties:
    
    /// An array of the popular categories to display:
    let categories: [NT_CoursesCategory]
    
    init(categories: [NT_CoursesCategory]) {
        
        /// Properties initialization:
        self.categories = categories
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

private extension MainTwoPopularCategoriesView {
    private var item: some View {
        Section("Popular Categories") {
            categoriesContent
        }
    }
}

// MARK: - Categories:

private extension MainTwoPopularCategoriesView {
    private var categoriesContent: some View {
        ForEach(
            categories,
            content: category
        )
    }
    
    private func category(_ category: NT_CoursesCategory) -> some View {
        NavigationLink(value: category) {
            categoryLabel(category)
        }
    }
    
    private func categoryLabel(_ category: NT_CoursesCategory) -> some View {
        IconBackgroundTitleSubtitleView(
            icon: icon(category),
            iconBackgroundColor: color(category),
            iconBackgroundGradientStart: gradientStart(category),
            iconBackgroundGradientEnd: gradientEnd(category),
            title: title(category),
            subtitle: coursesCount(category),
            verticalPadding: 0,
            horizontalPadding: 0,
            isShowingBackground: false,
            cornerRadius: 0
        )
    }
}

// MARK: - Preview:

#Preview {
    List {
        MainTwoPopularCategoriesView(categories: NT_CoursesCategory.example)
    }
    .listStyle(.plain)
    .localizedNavigationTitle(title: "Courses")
    .navigationDestination(for: NT_CoursesCategory.self) { category in
        PlaceholderView(title: category.title)
    }
    .navigationStack()
}
