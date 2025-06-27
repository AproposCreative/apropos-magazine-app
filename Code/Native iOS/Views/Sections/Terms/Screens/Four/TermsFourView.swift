//
//  TermsFourView.swift
//  Native
//

import SwiftUI

struct TermsFourView: View {
    
    // MARK: - Properties:
    
    /// An array of the sections with the terms to display:
    @State var sections: [NT_TermsSection] = []
    
    /// 'Bool' value indicating whether or not the data is currently being fetched:
    @State var isFetching: Bool = true
    
    // MARK: - Private properties:
    
    /// Dismisses the view:
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        scroll
            .localizedNavigationTitle(title: "Privacy Policy")
            .toolbarButton(
                title: "Done",
                action: dismiss.callAsFunction
            )
            .animation(
                .default,
                value: sections
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

// MARK: - Scroll:

private extension TermsFourView {
    private var scroll: some View {
        scrollContent
            .safeAreaPadding(
                .all,
                16
            )
            .safeAreaPadding(
                .bottom,
                16
            )
    }
    
    private var scrollContent: some View {
        ScrollView {
            scrollItem
        }
    }
    
    @ViewBuilder
    private var scrollItem: some View {
        if isFetching {
            loading
        } else if isEmpty {
            noTerms
        } else {
            TermsFourSectionsView(sections: sections)
        }
    }
}

// MARK: - Empty states:

private extension TermsFourView {
    private var loading: some View {
        loadingContent
            .frame(
                maxWidth: .infinity,
                alignment: .center
            )
            .containerRelativeFrame(
                .vertical,
                alignment: .center
            )
    }
    
    private var loadingContent: some View {
        LoadingView(
            isShowing: true,
            color: .secondary,
            scale: 1.5
        )
    }
    
    private var noTerms: some View {
        noTermsContent
            .frame(
                maxWidth: .infinity,
                alignment: .center
            )
            .containerRelativeFrame(
                .vertical,
                alignment: .center
            )
    }
    
    private var noTermsContent: some View {
        EmptyStateView(
            title: "No Terms",
            subtitle: "We don't have any terms to display here."
        )
    }
}

// MARK: - Preview:

#Preview {
    TermsFourView()
}
