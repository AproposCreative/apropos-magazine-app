//
//  FileEditingTwoView.swift
//  Native
//

import SwiftUI

struct FileEditingTwoView: View {
    
    // MARK: - Properties:
    
    /// An array of the categories to display:
    @State var categories: [NT_PhotoEditorCategory] = []
    
    /// 'Bool' value indicating whether or not the data is currently being fetched:
    @State var isFetching: Bool = true
    
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
                noCategories
            }
            .localizedNavigationTitle(title: "Categories")
            .navigationDestination(
                for: NT_PhotoEditorCategory.self,
                destination: FileEditingTwoPhotosView.init
            )
            .animation(
                .default,
                value: categories
            )
            .animation(
                .default,
                value: isFetching
            )
            .task {
                await fetchData()
            }
            .navigationStack()
    }
}

// MARK: - Empty states:

private extension FileEditingTwoView {
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
    
    private var noCategories: some View {
        noCategoriesContent
            .opacity(noCategoriesOpacity)
    }
    
    private var noCategoriesContent: some View {
        EmptyStateView(
            title: "No Categories",
            subtitle: "We don't have any categories to display here."
        )
    }
}

// MARK: - List:

private extension FileEditingTwoView {
    private var list: some View {
        listContent
            .listStyle(.insetGrouped)
    }
    
    private var listContent: some View {
        List {
            categoriesContent
        }
    }
}

// MARK: - Categories:

private extension FileEditingTwoView {
    private var categoriesContent: some View {
        ForEach(
            categories,
            content: category
        )
    }
    
    private func category(_ category: NT_PhotoEditorCategory) -> some View {
        NavigationLink(value: category) {
            categoryLabel(category)
        }
    }
    
    private func categoryLabel(_ category: NT_PhotoEditorCategory) -> some View {
        LabelView(
            icon: icon(category),
            title: title(category)
        )
    }
}

// MARK: - Preview:

#Preview {
    FileEditingTwoView()
}
