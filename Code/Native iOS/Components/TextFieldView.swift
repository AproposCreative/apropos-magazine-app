//
//  TextFieldView.swift
//  Native
//

import SwiftUI

struct TextFieldView: View {
    
    // MARK: - Private properties:
    
    /// An actual text that is inputed into the text field:
    @Binding private var text: String
    
    /// Title of the text field:
    private let title: String
    
    /// 'Bool' value indicating whether or not the title of the text field should be localized:
    private let isTitleLocalized: Bool
    
    /// Type of the keyboard that the text field should have (Only applicable on iOS):
    private let keyboardType: UIKeyboardType
    
    /// 'Bool' value indicating whether or not the text field should be a secure field:
    private let isSecure: Bool
    
    /// Font of the text field:
    private let font: Font
    
    /// Alignment of the text field:
    private let alignment: TextAlignment
    
    /// Color of the value of the text field:
    private let valueColor: Color
    
    /// Vertical padding around the text field:
    private let verticalPadding: Double
    
    /// Horizontal padding around the text field:
    private let horizontalPadding: Double
    
    /// Minimum height that the text field should have if applicable:
    private let minHeight: CGFloat?
    
    /// Alignment of the text field if it has a minimum height applied to it:
    private let minHeightAlignment: Alignment
    
    /// 'Bool' value indicating whether or not the background of the text field should be shown at all:
    private let isShowingBackground: Bool
    
    /// Color of the background of the text field:
    private let backgroundColor: Color
    
    /// Radius of the rounded corners of the text field:
    private let cornerRadius: Double
    
    /// Style of the rounded corners of the text field:
    private let cornerStyle: RoundedCornerStyle
    
    /// 'Bool' value indicating whether or not the text field should be disabled:
    private let isDisabled: Bool
    
    init(
        text: Binding<String>,
        title: String,
        isTitleLocalized: Bool = true,
        keyboardType: UIKeyboardType = .default,
        isSecure: Bool = false,
        font: Font = .headline,
        alignment: TextAlignment = .leading,
        valueColor: Color = .primary,
        verticalPadding: Double = 12,
        horizontalPadding: Double = 12,
        minHeight: CGFloat? = nil,
        minHeightAlignment: Alignment = .topLeading,
        isShowingBackground: Bool = true,
        backgroundColor: Color = .init(.secondarySystemBackground),
        cornerRadius: Double = 14,
        cornerStyle: RoundedCornerStyle = .continuous,
        isDisabled: Bool = false
    ) {
        
        /// Properties initialization:
        _text = text
        self.title = title
        self.isTitleLocalized = isTitleLocalized
        self.keyboardType = keyboardType
        self.isSecure = isSecure
        self.font = font
        self.alignment = alignment
        self.valueColor = valueColor
        self.verticalPadding = verticalPadding
        self.horizontalPadding = horizontalPadding
        self.minHeight = minHeight
        self.minHeightAlignment = minHeightAlignment
        self.isShowingBackground = isShowingBackground
        self.backgroundColor = backgroundColor
        self.cornerRadius = cornerRadius
        self.cornerStyle = cornerStyle
        self.isDisabled = isDisabled
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the text is currently empty:
    private var isTextEmpty: Bool {
        text.isEmpty
    }
    
    /// Content of the color of the background of the text field:
    private var backgroundColorContent: Color {
        if isShowingBackground {
            return backgroundColor
        } else {
            return .clear
        }
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .keyboardType(keyboardType)
            .font(font)
            .multilineTextAlignment(alignment)
            .foregroundStyle(valueColor)
            .padding(
                .vertical,
                verticalPadding
            )
            .padding(
                .horizontal,
                horizontalPadding
            )
            .frame(
                minHeight: minHeight,
                alignment: minHeightAlignment
            )
            .background(backgroundColorContent)
            .cornerRadius(cornerRadius)
            .roundedCorners(
                cornerRadius: cornerRadius,
                cornerStyle: cornerStyle
            )
            .disabled(isDisabled)
            .textFieldStyle(.plain)
    }
}

// MARK: - Item:

private extension TextFieldView {
    @ViewBuilder
    private var item: some View {
        if isSecure {
            secureItem
        } else {
            regularItem
        }
    }
    
    private var secureItem: some View {
        SecureField(text: $text) {
            itemLabel
        }
    }
    
    private var regularItem: some View {
        TextField(text: $text) {
            itemLabel
        }
    }
    
    @ViewBuilder
    private var itemLabel: some View {
        if isTitleLocalized {
            Text(.init(title))
        } else {
            Text(title)
        }
    }
}

// MARK: - Preview:

#Preview {
    @Previewable @State var text: String = "info@applayouts.com"
    
    ScrollView {
        TextFieldView(
            text: $text,
            title: "Email",
            keyboardType: .default,
            isSecure: false,
            font: .headline,
            alignment: .leading,
            valueColor: .primary,
            verticalPadding: 12,
            horizontalPadding: 12,
            minHeight: nil,
            minHeightAlignment: .topLeading,
            isShowingBackground: true,
            backgroundColor: .init(.secondarySystemGroupedBackground),
            cornerRadius: 14,
            cornerStyle: .continuous,
            isDisabled: false
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
