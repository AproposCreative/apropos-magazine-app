//
//  SortAndFilterSectionRowView.swift
//  Native
//

import SwiftUI

struct SortAndFilterSectionRowView: View {
    
    // MARK: - Properties:
    
    /// An actual screen to display:
    let screen: NT_SortAndFilterScreen
    
    // MARK: - Private properties:
    
    /// An action to view the screen:
    private let viewAction: (_ screen: NT_SortAndFilterScreen) -> ()
    
    init(
        screen: NT_SortAndFilterScreen,
        viewAction: @escaping (_ screen: NT_SortAndFilterScreen) -> ()
    ) {
        
        /// Properties initialization:
        self.screen = screen
        self.viewAction = viewAction
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .foregroundStyle(.primary)
    }
}

// MARK: - Item:

private extension SortAndFilterSectionRowView {
    private var item: some View {
        Button {
            viewAction(screen)
        } label: {
            label
        }
    }
}

// MARK: - Label:

private extension SortAndFilterSectionRowView {
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
            .foregroundStyle(
                .white,
                LinearGradient.blue
            )
    }
}

// MARK: - Preview:

#Preview {
    SortAndFilterSectionRowView(screen: .first) { _ in }
}
