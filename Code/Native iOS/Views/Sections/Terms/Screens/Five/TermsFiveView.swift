//
//  TermsFiveView.swift
//  Native
//

import SwiftUI

struct TermsFiveView: View {
    
    // MARK: - Properties:
    
    /// An array of the overview items for the terms to display:
    @State var overviewItems: [NT_TermsOverview] = []
    
    /// An array of the sections with the terms to display:
    @State var sections: [NT_TermsSection] = []
    
    /// 'Bool' value indicating whether or not the data is currently being fetched:
    @State var isFetching: Bool = true
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .background(backgroundColor)
            .localizedNavigationTitle(title: "Terms of Service")
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

// MARK: - Item:

private extension TermsFiveView {
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

private extension TermsFiveView {
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
            overviewSections
        }
    }
}

// MARK: - Empty states:

private extension TermsFiveView {
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

// MARK: - Overview and sections:

private extension TermsFiveView {
    private var overviewSections: some View {
        VStack(
            alignment: .leading,
            spacing: 32
        ) {
            overviewSectionsContent
        }
    }
    
    @ViewBuilder
    private var overviewSectionsContent: some View {
        TermsFiveOverviewView(overviewItems: overviewItems)
        TermsFiveSectionsView(sections: sections)
    }
}

// MARK: - Toolbar:

private extension TermsFiveView {
    private var toolbar: some View {
        BottomToolbarView(
            spacing: 8,
            backgroundColor: backgroundColor
        ) {
            acceptDownloadPDFButton
        }
    }
    
    @ViewBuilder
    private var acceptDownloadPDFButton: some View {
        acceptButton
        downloadPDFButton
    }
    
    private var acceptButton: some View {
        ButtonView(
            title: "Accept",
            icon: Icons.checkmarkCircle,
            style: buttonStyle,
            isDisabled: isEmpty,
            action: accept
        )
    }
    
    private var downloadPDFButton: some View {
        ButtonView(
            title: "Download PDF",
            titleColor: .primary,
            icon: Icons.squareAndArrowDown,
            isIconColorGradient: true,
            style: buttonStyle,
            backgroundColor: .init(.secondarySystemGroupedBackground),
            isBackgroundColorGradient: false,
            isDisabled: isEmpty,
            action: downloadPDF
        )
    }
}

// MARK: - Preview:

#Preview {
    TermsFiveView()
}
