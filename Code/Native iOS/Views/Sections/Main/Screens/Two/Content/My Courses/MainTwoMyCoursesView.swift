//
//  MainTwoMyCoursesView.swift
//  Native
//

import SwiftUI

struct MainTwoMyCoursesView: View {
    
    // MARK: - Properties:
    
    /// An array of the courses to display:
    let courses: [NT_Course]
    
    init(courses: [NT_Course]) {
        
        /// Properties initialization:
        self.courses = courses
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

private extension MainTwoMyCoursesView {
    private var item: some View {
        Section("My Courses") {
            coursesContent
        }
    }
}

// MARK: - Courses:

private extension MainTwoMyCoursesView {
    private var coursesContent: some View {
        ForEach(
            courses,
            content: course
        )
    }
    
    private func course(_ course: NT_Course) -> some View {
        NavigationLink {
            PlaceholderView(title: title(course))
        } label: {
            courseLabel(course)
        }
    }
    
    private func courseLabel(_ course: NT_Course) -> some View {
        ImageBackgroundTitleSubtitleProgressView(
            image: image(course),
            title: title(course),
            subtitle: completedLessonsCount(course),
            progressValue: completedLessonsCount(course),
            progressTotal: lessonsCount(course),
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
        MainTwoMyCoursesView(courses: .init(NT_Course.example.suffix(5)))
    }
    .listStyle(.plain)
    .localizedNavigationTitle(title: "Courses")
    .navigationDestination(for: NT_Course.self) { category in
        PlaceholderView(title: category.title)
    }
    .navigationStack()
}
