//
//  TermsOneView.swift
//  Native
//

import SwiftUI

struct TermsOneView: View {
    
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
        item
            .background(Color(.systemGroupedBackground))
            .localizedNavigationTitle(title: "Terms of Service")
            .toolbarButton(
                title: "Dismiss",
                icon: Icons.xmarkCircle,
                color: .init(.tertiaryLabel),
                style: .iconOnly,
                placement: .cancellationAction,
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

// MARK: - Item:

private extension TermsOneView {
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
        scroll
        toolbar
    }
}

// MARK: - Scroll:

private extension TermsOneView {
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
            TermsOneSectionsView(sections: sections)
        }
    }
}

// MARK: - Empty states:

private extension TermsOneView {
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

// MARK: - Toolbar:

private extension TermsOneView {
    private var toolbar: some View {
        BottomToolbarView() {
            acceptButton
        }
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
    TermsOneView()
}
