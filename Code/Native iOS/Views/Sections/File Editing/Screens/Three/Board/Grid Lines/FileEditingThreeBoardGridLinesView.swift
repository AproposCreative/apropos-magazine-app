//
//  FileEditingThreeBoardGridLinesView.swift
//  Native
//

import SwiftUI

struct FileEditingThreeBoardGridLinesView: View {
    
    // MARK: - Properties:
    
    /// The proxy of the geometry reader to get the correct size of the view:
    let proxy: GeometryProxy
    
    init(proxy: GeometryProxy) {
        
        /// Properties initialization:
        self.proxy = proxy
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        ScrollView(
            [
                .vertical,
                .horizontal
            ]
        ) {
            item
        }
    }
}

// MARK: - Item:

private extension FileEditingThreeBoardGridLinesView {
    private var item: some View {
        ZStack(alignment: .topLeading) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        verticalGridLinesContent
        horizontalGridLinesContent
    }
}

// MARK: - Vertical grid lines:

private extension FileEditingThreeBoardGridLinesView {
    private var verticalGridLinesContent: some View {
        LazyVStack(
            alignment: .leading,
            spacing: spacing
        ) {
            verticalGridLinesItem
        }
    }
    
    private var verticalGridLinesItem: some View {
        ForEach(
            verticalGridLines,
            id: \.self,
            content: verticalGridLine
        )
    }
    
    private func verticalGridLine(_ index: Int) -> some View {
        Rectangle()
            .foregroundStyle(color)
            .frame(
                height: frame,
                alignment: .topLeading
            )
    }
}

// MARK: - Horizontal grid lines:

private extension FileEditingThreeBoardGridLinesView {
    private var horizontalGridLinesContent: some View {
        LazyHStack(
            alignment: .top,
            spacing: spacing
        ) {
            horizontalGridLinesItem
        }
    }
    
    private var horizontalGridLinesItem: some View {
        ForEach(
            horizontalGridLines,
            id: \.self,
            content: horizontalGridLine
        )
    }
    
    private func horizontalGridLine(_ index: Int) -> some View {
        Rectangle()
            .foregroundStyle(color)
            .frame(
                width: frame,
                alignment: .topLeading
            )
    }
}

// MARK: - Preview:

#Preview {
    GeometryReader { proxy in
        ScrollView(
            [
                .vertical,
                .horizontal
            ]
        ) {
            Text("Preview")
                .padding()
                .frame(
                    width: 400,
                    height: 400,
                    alignment: .center
                )
                .background {
                    FileEditingThreeBoardGridLinesView(proxy: proxy)
                }
        }
    }
}
