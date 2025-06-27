//
//  BottomToolbarView.swift
//  Native
//

import SwiftUI

struct BottomToolbarView<ToolbarContent: View>: View {
    
    // MARK: - Private properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    /// Horizontal alignment of the content of the toolbar:
    private let horizontalAlignment: HorizontalAlignment
    
    /// Vertical alignment of the content of the toolbar:
    private let verticalAlignment: VerticalAlignment
    
    /// Spacing between the content of the toolbar:
    private let spacing: Double
    
    /// Vertical padding around the content of the toolbar:
    private let verticalPadding: Double
    
    /// Horizontal padding around the content of the toolbar:
    private let horizontalPadding: Double
    
    /// 'Bool' value indicating whether or not the divider should be shown at all:
    private let isShowingDivider: Bool
    
    /// Color of the divider:
    private let dividerColor: Color
    
    /// Alignment of the content of the toolbar:
    private let contentAlignment: NT_Alignment
    
    /// Color of the background of the toolbar:
    private let backgroundColor: Color
    
    /// An actual content to display in the toolbar:
    private let toolbarContent: ToolbarContent
    
    init(
        horizontalAlignment: HorizontalAlignment = .leading,
        verticalAlignment: VerticalAlignment = .top,
        spacing: Double = 16,
        verticalPadding: Double = 16,
        horizontalPadding: Double = 16,
        isShowingDivider: Bool = false,
        dividerColor: Color = .init(.tertiaryLabel),
        contentAlignment: NT_Alignment = .vertical,
        backgroundColor: Color = .clear,
        @ViewBuilder
        toolbarContent: @escaping () -> ToolbarContent
    ) {
        
        /// Properties initialization:
        self.horizontalAlignment = horizontalAlignment
        self.verticalAlignment = verticalAlignment
        self.spacing = spacing
        self.verticalPadding = verticalPadding
        self.horizontalPadding = horizontalPadding
        self.isShowingDivider = isShowingDivider
        self.dividerColor = dividerColor
        self.contentAlignment = contentAlignment
        self.backgroundColor = backgroundColor
        self.toolbarContent = toolbarContent()
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be moved that is based on the size of the dynamic type that is currently selected:
    private var shouldMoveContent: Bool {
        dynamicTypeSize >= .accessibility1
    }
    
    /// Maximum height of the toolbar:
    private var maxHeight: CGFloat? {
        shouldMoveContent ? 200 : nil
    }
    
    /// Value of the alignment of the content of the view that is based on the size of the dynamic type that is currently selected:
    private var contentAlignmentValue: NT_Alignment {
        shouldMoveContent ? .vertical : contentAlignment
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .frame(
                maxWidth: .infinity,
                maxHeight: maxHeight,
                alignment: .top
            )
            .background(backgroundColor)
    }
}

// MARK: - Item:

private extension BottomToolbarView {
    private var item: some View {
        VStack(
            alignment: horizontalAlignment,
            spacing: 0
        ) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        divider
        toolbar
    }
}

// MARK: - Divider:

private extension BottomToolbarView {
    @ViewBuilder
    private var divider: some View {
        if isShowingDivider {
            dividerContent
        }
    }
    
    private var dividerContent: some View {
        Rectangle()
            .fill(dividerColor)
            .frame(
                height: 0.5,
                alignment: .leading
            )
    }
}

// MARK: - Toolbar:

private extension BottomToolbarView {
    @ViewBuilder
    private var toolbar: some View {
        if shouldMoveContent {
            toolbarScroll
        } else {
            toolbarItem
        }
    }
    
    private var toolbarScroll: some View {
        toolbarScrollContent
            .scrollIndicators(.hidden)
    }
    
    private var toolbarScrollContent: some View {
        ScrollView {
            toolbarItem
        }
    }
    
    private var toolbarItem: some View {
        toolbarItemContent
            .padding(
                .vertical,
                verticalPadding
            )
            .padding(
                .horizontal,
                horizontalPadding
            )
    }
    
    @ViewBuilder
    private var toolbarItemContent: some View {
        switch contentAlignmentValue {
        case .vertical: verticalToolbarItemContent
        case .horizontal: horizontalToolbarItemContent
        }
    }
    
    private var verticalToolbarItemContent: some View {
        VStack(
            alignment: horizontalAlignment,
            spacing: spacing
        ) {
            toolbarContent
        }
    }
    
    private var horizontalToolbarItemContent: some View {
        HStack(
            alignment: verticalAlignment,
            spacing: spacing
        ) {
            toolbarContent
        }
    }
}

// MARK: - Preview:

#Preview {
    VStack(
        alignment: .leading,
        spacing: 0
    ) {
        ScrollView {  }
        
        BottomToolbarView(
            horizontalAlignment: .center,
            verticalAlignment: .center,
            spacing: 16,
            verticalPadding: 16,
            horizontalPadding: 16,
            isShowingDivider: true,
            dividerColor: .init(.tertiaryLabel),
            contentAlignment: .vertical,
            backgroundColor: .clear
        ) {
            Text("Toolbar Content")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }
}
