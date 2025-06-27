//
//  MainTwoJustForYouView.swift
//  Native
//

import SwiftUI

struct MainTwoJustForYouView: View {
    
    // MARK: - Properties:
    
    /// Horizontal size class of the device that the app is running on:
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    /// An array of the courses to display:
    let courses: [NT_Course]
    
    // MARK: - Private properties:
    
    /// Namespace that is needed for the zoom transition:
    @Namespace private var namespace
    
    /// Course that is currently shown:
    @Binding private var currentCourse: NT_Course?
    
    init(
        courses: [NT_Course],
        currentCourse: Binding<NT_Course?>
    ) {
        
        /// Properties initialization:
        self.courses = courses
        _currentCourse = currentCourse
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
            .listRowSeparator(.hidden)
            .headerProminence(.increased)
    }
}

// MARK: - Item:

private extension MainTwoJustForYouView {
    private var item: some View {
        Section("Just for You") {
            scroll
        }
    }
}

// MARK: - Scroll:

private extension MainTwoJustForYouView {
    private var scroll: some View {
        scrollContent
            .scrollIndicators(.hidden)
            .safeAreaPadding(
                .horizontal,
                16
            )
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $currentCourse)
            .listRowInsets(.init(.zero))
    }
    
    private var scrollContent: some View {
        ScrollView(.horizontal) {
            scrollItem
        }
    }
    
    private var scrollItem: some View {
        coursesContent
            .scrollTargetLayout()
    }
}

// MARK: - Courses:

private extension MainTwoJustForYouView {
    private var coursesContent: some View {
        LazyHStack(
            alignment: .top,
            spacing: spacing
        ) {
            coursesItem
        }
    }
    
    private var coursesItem: some View {
        ForEach(
            courses,
            content: course
        )
    }
    
    private func course(_ course: NT_Course) -> some View {
        courseContent(course)
            .matchedTransitionSource(
                id: identifier(course),
                in: namespace
            )
            .containerRelativeFrame(
                .horizontal,
                count: containerRelativeFrameCount,
                spacing: spacing
            )
            .scrollTransition(axis: .horizontal) { content, phase in
                content
                    .scaleEffect(scaleEffect(inPhase: phase))
            }
            .id(course)
    }
    
    private func courseContent(_ course: NT_Course) -> some View {
        NavigationLink {
            courseItem(course)
        } label: {
            courseLabel(course)
        }
    }
    
    private func courseItem(_ course: NT_Course) -> some View {
        PlaceholderView(title: title(course))
            .navigationTransition(
                .zoom(
                    sourceID: identifier(course),
                    in: namespace
                )
            )
    }
    
    private func courseLabel(_ course: NT_Course) -> some View {
        TitleSubtitleImageBackgroundView(
            title: title(course),
            subtitle: lessonsCount(course),
            image: image(course),
            imageHeight: imageHeight
        )
    }
}

// MARK: - Preview:

#Preview {
    List {
        MainTwoJustForYouView(
            courses: .init(NT_Course.example.prefix(3)),
            currentCourse: .constant(NT_Course.example.first)
        )
    }
    .listStyle(.plain)
    .localizedNavigationTitle(title: "Courses")
    .navigationStack()
}
