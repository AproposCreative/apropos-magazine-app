//
//  TermsThreeView.swift
//  Native
//

import SwiftUI

struct TermsThreeView: View {
    
    // MARK: - Properties:
    
    /// An array of the overview items for the terms to display:
    @State var overviewItems: [NT_TermsOverview] = []
    
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
        item
            .background(backgroundColor)
            .scrollContentBackground(.hidden)
            .overlay {
                loading
            }
            .overlay {
                noTerms
            }
            .localizedNavigationTitle(title: "Terms of Service")
            .toolbarButton(
                title: "Done",
                action: dismiss.callAsFunction
            )
            .animation(
                .default,
                value: overviewItems
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

// MARK: - Empty states:

private extension TermsThreeView {
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
    
    private var noTerms: some View {
        noTermsContent
            .opacity(noTermsOpacity)
    }
    
    private var noTermsContent: some View {
        EmptyStateView(
            title: "No Terms",
            subtitle: "We don't have any terms to display here."
        )
    }
}

// MARK: - Item:

private extension TermsThreeView {
    private var item: some View {
        VStack(
            alignment: .leading,
            spacing: 0
        ) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        list
        toolbar
    }
}

// MARK: - List:

private extension TermsThreeView {
    private var list: some View {
        listContent
            .listStyle(.insetGrouped)
    }
    
    private var listContent: some View {
        List {
            listItem
        }
    }
    
    @ViewBuilder
    private var listItem: some View {
        TermsThreeOverviewView(overviewItems: overviewItems)
        TermsThreeSectionsView(sections: sections)
    }
}

// MARK: - Toolbar:

private extension TermsThreeView {
    private var toolbar: some View {
        BottomToolbarView(
            spacing: 8,
            contentAlignment: .horizontal,
            backgroundColor: backgroundColor
        ) {
            declineAcceptButtons
        }
    }
    
    @ViewBuilder
    private var declineAcceptButtons: some View {
        declineButton
        acceptButton
    }
    
    private var declineButton: some View {
        ButtonView(
            title: "Decline",
            titleColor: .primary,
            backgroundColor: .init(.secondarySystemGroupedBackground),
            isBackgroundColorGradient: false,
            isDisabled: isEmpty,
            action: decline
        )
    }
    
    private var acceptButton: some View {
        ButtonView(
            title: "Accept",
            isDisabled: isEmpty,
            action: accept
        )
    }
}

// MARK: - Preview:

#Preview {
    TermsThreeView()
}
