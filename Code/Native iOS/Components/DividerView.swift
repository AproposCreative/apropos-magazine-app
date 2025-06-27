//
//  DividerView.swift
//  Native
//

import SwiftUI

struct DividerView: View {
    
    // MARK: - Private properties:
    
    /// 'Bool' value indicating whether or not the divider should be shown at all:
    private let isShowing: Bool
    
    /// Width that the divider should have if applicable:
    private let width: CGFloat?
    
    /// Height that the divider should have if applicable:
    private let height: CGFloat?
    
    /// Color of the divider:
    private let color: Color
    
    /// Radius of the rounded corners of the divider:
    private let cornerRadius: Double
    
    /// Style of the rounded corners of the divider:
    private let cornerStyle: RoundedCornerStyle
    
    /// Alignment of the divider:
    private let alignment: NT_Alignment
    
    init(
        isShowing: Bool = true,
        width: CGFloat? = nil,
        height: CGFloat? = 1,
        color: Color = .init(.systemFill),
        cornerRadius: Double = 0.5,
        cornerStyle: RoundedCornerStyle = .continuous,
        alignment: NT_Alignment = .vertical
    ) {
        
        /// Properties initialization:
        self.isShowing = isShowing
        self.width = width
        self.height = height
        self.color = color
        self.cornerRadius = cornerRadius
        self.cornerStyle = cornerStyle
        self.alignment = alignment
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

private extension DividerView {
    @ViewBuilder
    private var item: some View {
        switch alignment {
        case .vertical: verticalItem
        case .horizontal: horizontalItem
        }
    }
    
    private var verticalItem: some View {
        itemContent
            .frame(
                height: height,
                alignment: .center
            )
    }
    
    private var horizontalItem: some View {
        itemContent
            .frame(
                width: width,
                height: height,
                alignment: .center
            )
    }
    
    private var itemContent: some View {
        RoundedRectangle(
            cornerRadius: cornerRadius,
            style: cornerStyle
        )
        .fill(color)
    }
}

// MARK: - Preview:

#Preview {
    DividerView(
        isShowing: true,
        width: nil,
        height: 1,
        color: .init(.systemFill),
        cornerRadius: 0.5,
        cornerStyle: .continuous,
        alignment: .vertical
    )
    .padding()
    .frame(
        maxWidth: .infinity,
        maxHeight: .infinity,
        alignment: .center
    )
    .background(Color(.systemGroupedBackground))
}
