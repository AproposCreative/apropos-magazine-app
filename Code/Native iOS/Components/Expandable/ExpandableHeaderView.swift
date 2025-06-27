//
//  ExpandableHeaderView.swift
//  Native
//

import SwiftUI

struct ExpandableHeaderView: View {
    
    // MARK: - Private properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    /// 'Bool' value indicating whether or not the content should be expanded:
    @Binding private var isExpanded: Bool
    
    /// An actual title to display:
    private let title: String
    
    /// 'Bool' value indicating whether or not the title should be localized:
    private let isTitleLocalized: Bool
    
    /// Font of the title:
    private let titleFont: Font
    
    /// Text case of the title:
    private let titleTextCase: Text.Case?
    
    /// Alignment of the title:
    private let titleAlignment: TextAlignment
    
    /// Additional spacing between the multiple lines of the title:
    private let titleLineSpacing: Double
    
    /// Color of the title:
    private let titleColor: Color?
    
    /// Icon of the 'Expand' button:
    private let expandButtonIcon: String
    
    /// Symbol variant of the 'Expand' button (It could be '.fill', '.circle', etc.):
    private let expandButtonSymbolVariant: SymbolVariants
    
    /// Color of the 'Expand' button:
    private let expandButtonColor: Color
    
    /// Starting color of the gradient of the 'Expand' button if applicable:
    private let expandButtonGradientStart: Color
    
    /// Ending color of the gradient of the 'Expand' button if applicable:
    private let expandButtonGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the 'Expand' button should have a gradient applied to it:
    private let isExpandButtonColorGradient: Bool
    
    /// Size of the icon of the 'Expand' button:
    private let expandButtonIconSize: NT_IconSize
    
    /// Alignment of the content of the view:
    private let alignment: VerticalAlignment
    
    /// Spacing between the content of the view:
    private let spacing: Double
    
    /// Vertical padding around the content of the view:
    private let verticalPadding: Double
    
    /// Horizontal padding around the content of the view:
    private let horizontalPadding: Double
    
    /// 'Bool' value indicating whether or not the haptic feedback should be triggered after expanding or collapsing the header:
    private let isExpandHapticFeedbackEnabled: Bool
    
    init(
        isExpanded: Binding<Bool>,
        title: String,
        isTitleLocalized: Bool = true,
        titleFont: Font = .title3.bold(),
        titleTextCase: Text.Case? = .none,
        titleAlignment: TextAlignment = .leading,
        titleLineSpacing: Double = 0,
        titleColor: Color? = .primary,
        expandButtonIcon: String = Icons.chevronRight,
        expandButtonSymbolVariant: SymbolVariants = .fill,
        expandButtonColor: Color = .accent,
        expandButtonGradientStart: Color = .blueGradientStart,
        expandButtonGradientEnd: Color = .blueGradientEnd,
        isExpandButtonColorGradient: Bool = true,
        expandButtonIconSize: NT_IconSize = .custom(
            font: .headline,
            nonBackgroundFont: .headline,
            frame: 25,
            cornerRadius: 0,
            cornerStyle: .continuous
        ),
        alignment: VerticalAlignment = .top,
        spacing: Double = 12,
        verticalPadding: Double = 0,
        horizontalPadding: Double = 0,
        isExpandHapticFeedbackEnabled: Bool = true
    ) {
        
        /// Properties initialization:
        _isExpanded = isExpanded
        self.title = title
        self.isTitleLocalized = isTitleLocalized
        self.titleFont = titleFont
        self.titleTextCase = titleTextCase
        self.titleAlignment = titleAlignment
        self.titleLineSpacing = titleLineSpacing
        self.titleColor = titleColor
        self.expandButtonIcon = expandButtonIcon
        self.expandButtonSymbolVariant = expandButtonSymbolVariant
        self.expandButtonColor = expandButtonColor
        self.expandButtonGradientStart = expandButtonGradientStart
        self.expandButtonGradientEnd = expandButtonGradientEnd
        self.isExpandButtonColorGradient = isExpandButtonColorGradient
        self.expandButtonIconSize = expandButtonIconSize
        self.alignment = alignment
        self.spacing = spacing
        self.verticalPadding = verticalPadding
        self.horizontalPadding = horizontalPadding
        self.isExpandHapticFeedbackEnabled = isExpandHapticFeedbackEnabled
    }
    
    // MARK: - Private computed properties:
    
    /// Accessibility label of the 'Expand' button that is based on whether or not it's currently expanded:
    private var expandButtonAccessibilityLabel: String {
        expandButtonAccessibilityLabelTitle + " " + (isExpanded ? .init(localized: "Collapse") : .init(localized: "Expand"))
    }
    
    /// Title of the accessibility label of the 'Expand' button:
    private var expandButtonAccessibilityLabelTitle: String {
        if isTitleLocalized {
            return .init(localized: .init(title))
        } else {
            return title
        }
    }
    
    /// Rotation angle of the icon of the 'Expand' button that is based on whether or not the content is currently expanded:
    private var expandButtonAngle: Angle {
        isExpanded ? Angle(degrees: 90) : Angle(degrees: 0)
    }
    
    /// Value of the size of the icon of the 'Expand' button that is based on the size of the dynamic type that is currently selected:
    private var expandButtonIconSizeValue: NT_IconSize {
        dynamicTypeSize >= .accessibility1 ? .custom(
            font: expandButtonIconSize.font,
            nonBackgroundFont: expandButtonIconSize.nonBackgroundFont,
            frame: nil,
            cornerRadius: expandButtonIconSize.cornerRadius,
            cornerStyle: expandButtonIconSize.cornerStyle
        ) : expandButtonIconSize
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .buttonStyle(.plain)
            .accessibilityLabel(expandButtonAccessibilityLabel)
    }
}

// MARK: - Item:

private extension ExpandableHeaderView {
    private var item: some View {
        Button {
            expand()
        } label: {
            label
        }
    }
}

// MARK: - Label:

private extension ExpandableHeaderView {
    private var label: some View {
        labelContent
            .padding(
                .vertical,
                verticalPadding
            )
            .padding(
                .horizontal,
                horizontalPadding
            )
    }
    
    private var labelContent: some View {
        HStack(
            alignment: alignment,
            spacing: spacing
        ) {
            labelItem
        }
    }
    
    @ViewBuilder
    private var labelItem: some View {
        titleContent
        expandButton
    }
}

// MARK: - Title:

private extension ExpandableHeaderView {
    private var titleContent: some View {
        titleItem
            .font(titleFont)
            .textCase(titleTextCase)
            .multilineTextAlignment(titleAlignment)
            .lineSpacing(titleLineSpacing)
            .optionalForegroundStyle(titleColor)
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
            .accessibilityAddTraits(.isHeader)
    }
    
    @ViewBuilder
    private var titleItem: some View {
        if isTitleLocalized {
            Text(.init(title))
        } else {
            Text(title)
        }
    }
}

// MARK: - Expand button:

private extension ExpandableHeaderView {
    private var expandButton: some View {
        expandButtonContent
            .rotationEffect(expandButtonAngle)
    }
    
    private var expandButtonContent: some View {
        LabelView(
            icon: expandButtonIcon,
            iconSymbolVariant: expandButtonSymbolVariant,
            iconColor: expandButtonColor,
            iconGradientStart: expandButtonGradientStart,
            iconGradientEnd: expandButtonGradientEnd,
            isIconColorGradient: isExpandButtonColorGradient,
            iconSize: expandButtonIconSizeValue,
            isShowingTitle: false,
            title: ""
        )
    }
}

// MARK: - Functions:

private extension ExpandableHeaderView {
    
    // MARK: - Private functions:
    
    /// Expands or collapses the content:
    private func expand() {
        
        /// Firstly adding an animation before toggling the 'isExpanded' property to collapse or expand the content:
        withAnimation {
            
            /// Then toggling the 'isExpanded' property to collapse or expand the content:
            isExpanded.toggle()
        }
        
        /// Lastly triggering the selection changed haptic feedback indicating that there was a change if needed:
        HapticFeedbacks.selectionChanged(isEnabled: isExpandHapticFeedbackEnabled)
    }
}

// MARK: - Preview:

#Preview {
    @Previewable @State var isExpanded: Bool = false
    
    ScrollView {
        ExpandableHeaderView(
            isExpanded: $isExpanded,
            title: "Title",
            isTitleLocalized: true,
            titleFont: .title3.bold(),
            titleTextCase: .none,
            titleAlignment: .leading,
            titleLineSpacing: 0,
            titleColor: .primary,
            expandButtonIcon: Icons.chevronRight,
            expandButtonSymbolVariant: .fill,
            expandButtonColor: .accent,
            expandButtonGradientStart: .blueGradientStart,
            expandButtonGradientEnd: .blueGradientEnd,
            isExpandButtonColorGradient: true,
            expandButtonIconSize: .custom(
                font: .headline,
                nonBackgroundFont: .headline,
                frame: 25,
                cornerRadius: 0,
                cornerStyle: .continuous
            ),
            alignment: .top,
            spacing: 12,
            verticalPadding: 0,
            horizontalPadding: 0,
            isExpandHapticFeedbackEnabled: true
        )
    }
    .safeAreaPadding(
        .all,
        16
    )
    .safeAreaPadding(
        .bottom,
        16
    )
    .background(Color(.systemGroupedBackground))
}
