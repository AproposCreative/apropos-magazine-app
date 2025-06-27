//
//  CategoryRowView.swift
//  Native
//

import SwiftUI

struct CategoryRowView: View {
    
    // MARK: - Properties:
    
    /// An actual category to display:
    let category: NT_Category
    
    init(category: NT_Category) {
        
        /// Properties initialization:
        self.category = category
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        NavigationLink(value: category) {
            label
        }
    }
}

// MARK: - Label:

private extension CategoryRowView {
    private var label: some View {
        labelContent
            .font(.headline)
            .multilineTextAlignment(.leading)
    }
    
    private var labelContent: some View {
        Label {
            Text(title)
        } icon: {
            iconContent
        }
    }
    
    private var iconContent: some View {
        Image(systemName: icon)
            .symbolVariant(.fill)
            .foregroundStyle(LinearGradient.blue)
    }
}

// MARK: - Preview:

#Preview {
    CategoryRowView(category: .onboarding)
}
