//
//  LoadingView.swift
//  Native
//

import SwiftUI

struct LoadingView: View {
    
    // MARK: - Private properties:
    
    /// 'Bool' value indicating whether or not the loading indicator should be shown at all:
    private let isShowing: Bool
    
    /// Title of the loading indicator if applicable:
    private let title: String?
    
    /// 'Bool' value indicating whether or not the title should be localized:
    private let isTitleLocalized: Bool
    
    /// Color of the loading indicator:
    private let color: Color
    
    /// Scale of the loading indicator ('1' is the default scale, anything that is more than one will increase the size of the indicator, but anything that is less than one will decrease its size):
    private let scale: Double
    
    /// Size of the frame of the view (If needed, can simply be 'nil'):
    private let frame: CGFloat?
    
    init(
        isShowing: Bool,
        title: String? = nil,
        isTitleLocalized: Bool = true,
        color: Color = .secondary,
        scale: Double = 1,
        frame: CGFloat? = nil
    ) {
        
        /// Properties initialization:
        self.isShowing = isShowing
        self.title = title
        self.isTitleLocalized = isTitleLocalized
        self.color = color
        self.scale = scale
        self.frame = frame
    }
    
    // MARK: - Private computed properties:
    
    /// Accessibility label of the view:
    private var accessibilityLabel: LocalizedStringKey {
        "Loading"
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    @ViewBuilder
    private var content: some View {
        if isShowing {
            item
        }
    }
}

// MARK: - Item:

private extension LoadingView {
    private var item: some View {
        itemContent
            .progressViewStyle(.circular)
            .tint(color)
            .scaleEffect(scale)
            .frame(
                width: frame,
                height: frame,
                alignment: .center
            )
            .accessibilityLabel(accessibilityLabel)
    }
    
    @ViewBuilder
    private var itemContent: some View {
        if let title {
            titleItem(title)
        } else {
            ProgressView()
        }
    }
    
    private func titleItem(_ title: String) -> some View {
        ProgressView {
            titleContent(title)
        }
    }
}

// MARK: - Title:

private extension LoadingView {
    @ViewBuilder
    private func titleContent(_ title: String) -> some View {
        if isTitleLocalized {
            Text(.init(title))
        } else {
            Text(title)
        }
    }
}

// MARK: - Preview:

#Preview {
    LoadingView(
        isShowing: true,
        title: "Title",
        isTitleLocalized: true,
        color: .secondary,
        scale: 1,
        frame: nil
    )
    .padding()
    .frame(
        maxWidth: .infinity,
        maxHeight: .infinity,
        alignment: .center
    )
    .background(Color(.systemGroupedBackground))
}
