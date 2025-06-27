//
//  CategoriesView.swift
//  Native
//

import SwiftUI

struct CategoriesView: View {
    
    // MARK: - Private properties:
    
    /// Category that is currently selected:
    @State private var selectedCategory: NT_Category? = nil
    
    // MARK: - View:
    
    var body: some View {
        navigationSplitView
    }
    
    private var navigationSplitView: some View {
        NavigationSplitView {
            content
        } detail: {
            detail
        }
    }
    
    private var content: some View {
        list
            .navigationTitle("AppLayouts")
    }
}

// MARK: - Detail:

private extension CategoriesView {
    @ViewBuilder
    private var detail: some View {
        switch selectedCategory {
        case .none: nothingSelected
        case .onboarding: OnboardingSectionView()
        case .signUp: SignUpSectionView()
        case .login: LoginSectionView()
        case .passwordReset: PasswordResetSectionView()
        case .paywall: PaywallSectionView()
        case .emptyState: EmptyStateSectionView()
        case .main: MainSectionView()
        case .productDetails: ProductDetailsSectionView()
        case .dataVisualization: DataVisualizationSectionView()
        case .fileEditing: FileEditingSectionView()
        case .sortAndFilter: SortAndFilterSectionView()
        case .profile: ProfileSectionView()
        case .account: AccountSectionView()
        case .settings: SettingsSectionView()
        case .terms: TermsSectionView()
        }
    }
    
    private var nothingSelected: some View {
        EmptyStateView()
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .center
            )
            .background(Color(.systemGroupedBackground))
    }
}

// MARK: - List:

private extension CategoriesView {
    private var list: some View {
        listContent
            .listStyle(.sidebar)
    }
    
    private var listContent: some View {
        List(selection: $selectedCategory) {
            categoriesContent
        }
    }
}

// MARK: - Categories:

private extension CategoriesView {
    private var categoriesContent: some View {
        ForEach(
            categories,
            content: CategoryRowView.init
        )
    }
}

// MARK: - Preview:

#Preview {
    CategoriesView()
}
