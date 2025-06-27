//
//  PaginationView.swift
//  Native
//

import SwiftUI

struct PaginationView<Page>: View where Page: Hashable {
    
    // MARK: - Private properties:
    
    /// Page that is currently selected:
    @Binding private var current: Page
    
    /// An array of all of the pages:
    private let all: [Page]
    
    /// Color of the dots of the pages:
    private let color: Color
    
    /// Starting color of the gradient of the dots of the pages if applicable:
    private let gradientStart: Color
    
    /// Ending color of the gradient of the dots of the pages if applicable:
    private let gradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the dots of the pages should have a gradient applied to it:
    private let isColorGradient: Bool
    
    /// Size of the frame of the dots of the pages:
    private let frame: Double
    
    /// Spacing between the dots of the pages:
    private let spacing: Double
    
    /// Vertical padding around the dots of the pagination:
    private let verticalPadding: Double
    
    /// Horizontal padding around the dots of the pagination:
    private let horizontalPadding: Double
    
    /// 'Bool' value indicating whether or not the haptic feedback should be triggered after selecting the page (Only applicable on iOS because other platforms don't support haptic feedbacks):
    private let isSelectionHapticFeedbackEnabled: Bool
    
    init(
        current: Binding<Page>,
        all: [Page],
        color: Color = .blue,
        gradientStart: Color = .blueGradientStart,
        gradientEnd: Color = .blueGradientEnd,
        isColorGradient: Bool = true,
        frame: Double = 8,
        spacing: Double = 10,
        verticalPadding: Double = 0,
        horizontalPadding: Double = 0,
        isSelectionHapticFeedbackEnabled: Bool = true
    ) {
       
        /// Properties initialization:
        _current = current
        self.all = all
        self.color = color
        self.gradientStart = gradientStart
        self.gradientEnd = gradientEnd
        self.isColorGradient = isColorGradient
        self.frame = frame
        self.spacing = spacing
        self.verticalPadding = verticalPadding
        self.horizontalPadding = horizontalPadding
        self.isSelectionHapticFeedbackEnabled = isSelectionHapticFeedbackEnabled
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be shown at all:
    private var isShowing: Bool {
        !all.isEmpty
    }
    
    /// Accessibility value of the view:
    private var accessibilityValue: LocalizedStringKey {
        "Item \((all.firstIndex(of: current) ?? 0) + 1) out of \(count)"
    }
    
    /// Count of all of the pages:
    private var count: Int {
        all.count
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    @ViewBuilder
    private var content: some View {
        if isShowing {
            mainContent
        }
    }
    
    private var mainContent: some View {
        item
            .padding(
                .vertical,
                verticalPadding
            )
            .padding(
                .horizontal,
                horizontalPadding
            )
            .accessibilityElement(children: .combine)
            .accessibilityValue(accessibilityValue)
            .accessibilityAdjustableAction(accessibilityAdjustableAction)
            .onChange(of: current) { _, _ in
                triggerHapticFeedback()
            }
    }
}

// MARK: - Item:

private extension PaginationView {
    private var item: some View {
        HStack(
            alignment: .center,
            spacing: spacing
        ) {
            pages
        }
    }
}

// MARK: - Pages:

private extension PaginationView {
    private var pages: some View {
        ForEach(
            all,
            id: \.self,
            content: page
        )
    }
    
    private func page(_ page: Page) -> some View {
        PaginationItemView(
            current: $current,
            page: page,
            color: color,
            gradientStart: gradientStart,
            gradientEnd: gradientEnd,
            isColorGradient: isColorGradient,
            frame: frame
        )
    }
}

// MARK: - Functions:

private extension PaginationView {
    
    // MARK: - Private functions:
    
    /// An accessibility action to adjust the value of the view that is based on the given direction:
    private func accessibilityAdjustableAction(_ direction: AccessibilityAdjustmentDirection) {
        
        /// Firstly making sure that we have the index of the current page:
        guard let index: Int = all.firstIndex(of: current) else { return }
        
        /// If yes, then switching on the direction to perform the right action:
        switch direction {
        case .increment:
            
            /// If it's an increment, then making sure that we can get the next page by enumerating an array of all of the pages and adding one to an index of the current page:
            if let nextPage: Page = all.enumerated().first(
                where: {
                    $0.offset == index + 1
                }
            )?.element {
                
                /// If yes, then assigning the next page as the current one:
                current = nextPage
            } else if let firstPage: Page = all.first {
                
                /// If we can't get the next page, then simply assigning the first page as the current one:
                current = firstPage
            }
        case .decrement:
            
            /// If it's a decrement, then making sure that we can get the next page by enumerating an array of all of the pages and subtracting one from an index of the current page:
            if let previousPage: Page = all.enumerated().first(
                where: {
                    $0.offset == index - 1
                }
            )?.element {
                
                /// If yes, then assigning the previous page as the current one:
                current = previousPage
            } else if let lastPage: Page = all.last {
                
                /// If we can't get the previous page, then simply assigning the last page as the current one:
                current = lastPage
            }
        @unknown default:
            
            /// If none of the above, then simply breaking:
            break
        }
    }
    
    /// Triggers the haptic feedback if needed:
    private func triggerHapticFeedback() {
        
        /// Triggering the selection changed haptic feedback indicating that there was a change if needed:
        HapticFeedbacks.selectionChanged(isEnabled: isSelectionHapticFeedbackEnabled)
    }
}

// MARK: - Preview:

#Preview {
    @Previewable @State var current: NT_PaginationExample = .first
    
    PaginationView(
        current: $current,
        all: NT_PaginationExample.allCases,
        color: .blue,
        gradientStart: .blueGradientStart,
        gradientEnd: .blueGradientEnd,
        isColorGradient: true,
        frame: 8,
        spacing: 10,
        verticalPadding: 0,
        horizontalPadding: 0,
        isSelectionHapticFeedbackEnabled: true
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

fileprivate enum NT_PaginationExample: Int, CaseIterable, Identifiable, Hashable {
    
    // MARK: - Cases:
    
    case first
    case second
    case third
    case fourth
    case fifth
    
    // MARK: - Computed properties:
    
    /// Identifier of the example:
    var id: Int {
        rawValue
    }
}
