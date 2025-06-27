//
//  TermsSectionRowView.swift
//  Native
//

import SwiftUI

struct TermsSectionRowView: View {
    
    // MARK: - Properties:
    
    /// An actual screen to display:
    let screen: NT_TermsScreen
    
    // MARK: - Private properties:
    
    /// An action to view the screen:
    private let viewAction: (_ screen: NT_TermsScreen) -> ()
    
    init(
        screen: NT_TermsScreen,
        viewAction: @escaping (_ screen: NT_TermsScreen) -> ()
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

private extension TermsSectionRowView {
    private var item: some View {
        Button {
            viewAction(screen)
        } label: {
            label
        }
    }
}

// MARK: - Label:

private extension TermsSectionRowView {
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
    TermsSectionRowView(screen: .first) { _ in }
}
