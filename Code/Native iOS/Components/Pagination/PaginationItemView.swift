//
//  PaginationItemView.swift
//  Native
//

import SwiftUI

struct PaginationItemView<Page: Hashable>: View {
    
    // MARK: - Private properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    /// Color scheme that is currently selected:
    @Environment(\.colorScheme) private var colorScheme
    
    /// Page that is currently selected:
    @Binding private var current: Page
    
    /// An actual page to display:
    private let page: Page
    
    /// Color of the page
    private let color: Color
    
    /// Starting color of the gradient of the page if applicable:
    private let gradientStart: Color
    
    /// Ending color of the gradient of the page if applicable:
    private let gradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the page should have a gradient applied to it:
    private let isColorGradient: Bool
    
    /// Size of the frame of the page:
    private let frame: Double
    
    init(
        current: Binding<Page>,
        page: Page,
        color: Color = .blue,
        gradientStart: Color = .blueGradientStart,
        gradientEnd: Color = .blueGradientEnd,
        isColorGradient: Bool = true,
        frame: Double
    ) {
        
        /// Properties initialization:
        _current = current
        self.page = page
        self.color = color
        self.gradientStart = gradientStart
        self.gradientEnd = gradientEnd
        self.isColorGradient = isColorGradient
        self.frame = frame
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the page is currently selected:
    private var isSelected: Bool {
        current == page
    }
    
    /// Content of the color of the page that is based on whether or not it's currently selected:
    private var colorContent: Color {
        isSelected ? color : color.opacity(unselectedOpacity)
    }
    
    /// Content of the starting color of the gradient of the page that is based on whether or not it's currently selected:
    private var gradientStartContent: Color {
        isSelected ? gradientStart : gradientStart.opacity(unselectedOpacity)
    }
    
    /// Content of the ending color of the gradient of the page that is based on whether or not it's currently selected:
    private var gradientEndContent: Color {
        isSelected ? gradientEnd : gradientEnd.opacity(unselectedOpacity)
    }
    
    /// Opacity of the page when it's not selected:
    private var unselectedOpacity: Double {
        colorScheme == .dark ? 0.32 : 0.16
    }
    
    /// Value of the frame of the view that is based on the size of the dynamic type that is currently selected:
    private var frameValue: Double {
        switch dynamicTypeSize {
        case .xSmall: return frame - 1.5
        case .small: return frame - 1
        case .medium: return frame - 0.5
        case .large: return frame
        case .xLarge: return frame + 0.5
        case .xxLarge: return frame + 1
        case .xxxLarge: return frame + 1.5
        case .accessibility1: return frame + 2
        case .accessibility2: return frame + 2.5
        case .accessibility3: return frame + 3
        case .accessibility4: return frame + 3.5
        case .accessibility5: return frame + 4
        @unknown default: return frame
        }
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .buttonStyle(.plain)
            .frame(
                width: frameValue,
                height: frameValue,
                alignment: .center
            )
    }
}

// MARK: - Item:

private extension PaginationItemView {
    private var item: some View {
        Button {
           select()
        } label: {
            itemLabel
        }
    }
    
    private var itemLabel: some View {
        Circle()
            .gradientFill(
                color: colorContent,
                gradientStart: gradientStartContent,
                gradientEnd: gradientEndContent,
                isGradient: isColorGradient
            )
    }
}

// MARK: - Functions:

private extension PaginationItemView {
    
    // MARK: - Private functions:
    
    /// Selects the page unless it's already selected:
    private func select() {
        
        /// Firstly making sure that the page isn't already selected:
        if !isSelected {
            
            /// If yes, then selecting the page:
            current = page
        }
    }
}

// MARK: - Preview:

#Preview {
    @Previewable @State var current: NT_PaginationExample = .first
    
    PaginationItemView(
        current: $current,
        page: NT_PaginationExample.first,
        color: .blue,
        gradientStart: .blueGradientStart,
        gradientEnd: .blueGradientEnd,
        isColorGradient: true,
        frame: 8
    )
    .padding()
    .frame(
        maxWidth: .infinity,
        maxHeight: .infinity,
        alignment: .center
    )
    .background(Color(.systemGroupedBackground))
}

// MARK: - Example:

fileprivate enum NT_PaginationExample: CaseIterable {
    
    // MARK: - Cases:
    
    case first
    case second
    case third
    case fourth
    case fifth
}
