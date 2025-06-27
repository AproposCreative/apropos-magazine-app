//
//  ImageBackgroundBorderTitleView.swift
//  Native
//

import SwiftUI

struct ImageBackgroundBorderTitleView: View {
    
    // MARK: - Private properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    /// An actual image to display:
    private let image: Image
    
    /// 'Bool' value indicating whether or not the image should be resizable or if it should just keep its original size:
    private let isImageResizable: Bool
    
    /// 'Bool' value indicating whether or not the image should be clipped based on its frame:
    private let isImageClipped: Bool
    
    /// Width of the image if applicable:
    private let imageWidth: CGFloat?
    
    /// Height of the image if applicable:
    private let imageHeight: CGFloat?
    
    /// Maximum width that the image should have if applicable:
    private let imageMaxWidth: CGFloat?
    
    /// Alignment of the image:
    private let imageAlignment: Alignment
    
    /// 'Bool' value indicating whether or not the image should take the full width:
    private let isImageFullWidth: Bool
    
    /// 'Bool' value indicating whether or not the background of the image should be shown at all:
    private let isShowingImageBackground: Bool
    
    /// Color of the background of the image:
    private let imageBackgroundColor: Color
    
    /// Starting color of the gradient of the background of the image if applicable:
    private let imageBackgroundGradientStart: Color
    
    /// Ending color of the gradient of the background of the image if applicable:
    private let imageBackgroundGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the background color of the image should have a gradient applied to it:
    private let isImageBackgroundColorGradient: Bool
    
    /// Radius of the rounded corners of the image:
    private let imageCornerRadius: Double
    
    /// Style of the rounded corners of the image:
    private let imageCornerStyle: RoundedCornerStyle
    
    /// Accessibility label of the image:
    private let imageAccessibilityLabel: String
    
    /// 'Bool' value indicating whether or not the accessibility label of the image should be localized:
    private let isImageAccessibilityLabelLocalized: Bool
    
    /// Width of the border of the image if applicable:
    private let imageBorderWidth: Double
    
    /// Color of the border of the image if applicable:
    private let imageBorderColor: Color
    
    /// Starting color of the gradient of the border of the image if applicable:
    private let imageBorderGradientStart: Color
    
    /// Ending color of the gradient of the border of the image if applicable:
    private let imageBorderGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the border of the image should have a gradient applied to it:
    private let isImageBorderColorGradient: Bool
    
    /// Size of the frame of the border of the image if applicable:
    private let imageBorderFrame: Double
    
    /// Radius of the rounded corners of the border of the image if applicable:
    private let imageBorderCornerRadius: Double
    
    /// Style of the rounded corners of the border of the image if applicable:
    private let imageBorderCornerStyle: RoundedCornerStyle
    
    /// 'Bool' value indicating whether or not the title should be shown at all:
    private let isShowingTitle: Bool
    
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
    private let titleColor: Color
    
    /// Starting color of the gradient of the title if applicable:
    private let titleGradientStart: Color
    
    /// Ending color of the gradient of the title if applicable:
    private let titleGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the title should have a gradient applied to it:
    private let isTitleColorGradient: Bool
    
    /// 'Bool' value indicating whether or not the content of the view should be placed in reverse meaning that the title would be displayed first and the image last:
    private let isReversed: Bool
    
    /// Alignment of the content of the view:
    private let alignment: NT_Alignment
    
    /// Vertical alignment of the content of the view:
    private let verticalAlignment: VerticalAlignment
    
    /// Horizontal alignment of the content of the view:
    private let horizontalAlignment: HorizontalAlignment
    
    /// Spacing between the content of the view:
    private let spacing: Double
    
    /// Vertical padding around the content of the view:
    private let verticalPadding: Double
    
    /// Horizontal padding around the content of the view:
    private let horizontalPadding: Double
    
    /// Maximum height that the view can have if applicable:
    private let maxHeight: CGFloat?
    
    /// Alignment of the view if it has a maximum height applied to it:
    private let maxHeightAlignment: Alignment
    
    /// 'Bool' value indicating whether or not the background of the view should be shown at all:
    private let isShowingBackground: Bool
    
    /// Color of the background of the view:
    private let backgroundColor: Color
    
    /// Starting color of the gradient of the background of the view if applicable:
    private let backgroundGradientStart: Color
    
    /// Ending color of the gradient of the background of the view if applicable:
    private let backgroundGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the background of the view should have a gradient applied to it:
    private let isBackgroundColorGradient: Bool
    
    /// Radius of the rounded corners of the view:
    private let cornerRadius: Double
    
    /// Style of the rounded corners of the view:
    private let cornerStyle: RoundedCornerStyle
    
    /// Action of the icon after single tapping on it if applicable:
    private let imageSingleTapAction: (() -> ())?
    
    /// Action of the icon after double tapping on it if applicable:
    private let imageDoubleTapAction: (() -> ())?
    
    init(
        image: Image,
        isImageResizable: Bool = true,
        isImageClipped: Bool = true,
        imageWidth: CGFloat? = 56,
        imageHeight: CGFloat? = 56,
        imageMaxWidth: CGFloat? = nil,
        imageAlignment: Alignment = .center,
        isImageFullWidth: Bool = false,
        isShowingImageBackground: Bool = false,
        imageBackgroundColor: Color = .accent,
        imageBackgroundGradientStart: Color = .blueGradientStart,
        imageBackgroundGradientEnd: Color = .blueGradientEnd,
        isImageBackgroundColorGradient: Bool = false,
        imageCornerRadius: Double = 28,
        imageCornerStyle: RoundedCornerStyle = .continuous,
        imageAccessibilityLabel: String = "",
        isImageAccessibilityLabelLocalized: Bool = true,
        imageBorderWidth: Double = 2,
        imageBorderColor: Color = .init(.secondarySystemGroupedBackground),
        imageBorderGradientStart: Color = .blueGradientStart,
        imageBorderGradientEnd: Color = .blueGradientEnd,
        isImageBorderColorGradient: Bool = true,
        imageBorderFrame: Double = 64,
        imageBorderCornerRadius: Double = 32,
        imageBorderCornerStyle: RoundedCornerStyle = .continuous,
        isShowingTitle: Bool = true,
        title: String,
        isTitleLocalized: Bool = true,
        titleFont: Font = .caption2.bold(),
        titleTextCase: Text.Case? = .none,
        titleAlignment: TextAlignment = .center,
        titleLineSpacing: Double = 0,
        titleColor: Color = .primary,
        titleGradientStart: Color = .blueGradientStart,
        titleGradientEnd: Color = .blueGradientEnd,
        isTitleColorGradient: Bool = false,
        isReversed: Bool = false,
        alignment: NT_Alignment = .vertical,
        verticalAlignment: VerticalAlignment = .top,
        horizontalAlignment: HorizontalAlignment = .center,
        spacing: Double = 6,
        verticalPadding: Double = 0,
        horizontalPadding: Double = 0,
        maxHeight: CGFloat? = nil,
        maxHeightAlignment: Alignment = .topLeading,
        isShowingBackground: Bool = false,
        backgroundColor: Color = .init(.secondarySystemGroupedBackground),
        backgroundGradientStart: Color = .blueGradientStart,
        backgroundGradientEnd: Color = .blueGradientEnd,
        isBackgroundColorGradient: Bool = false,
        cornerRadius: Double = 0,
        cornerStyle: RoundedCornerStyle = .continuous,
        imageSingleTapAction: (() -> ())? = nil,
        imageDoubleTapAction: (() -> ())? = nil
    ) {
        
        /// Properties initialization:
        self.image = image
        self.isImageResizable = isImageResizable
        self.isImageClipped = isImageClipped
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.imageMaxWidth = imageMaxWidth
        self.imageAlignment = imageAlignment
        self.isImageFullWidth = isImageFullWidth
        self.isShowingImageBackground = isShowingImageBackground
        self.imageBackgroundColor = imageBackgroundColor
        self.imageBackgroundGradientStart = imageBackgroundGradientStart
        self.imageBackgroundGradientEnd = imageBackgroundGradientEnd
        self.isImageBackgroundColorGradient = isImageBackgroundColorGradient
        self.imageCornerRadius = imageCornerRadius
        self.imageCornerStyle = imageCornerStyle
        self.imageAccessibilityLabel = imageAccessibilityLabel
        self.isImageAccessibilityLabelLocalized = isImageAccessibilityLabelLocalized
        self.imageBorderWidth = imageBorderWidth
        self.imageBorderColor = imageBorderColor
        self.imageBorderGradientStart = imageBorderGradientStart
        self.imageBorderGradientEnd = imageBorderGradientEnd
        self.isImageBorderColorGradient = isImageBorderColorGradient
        self.imageBorderFrame = imageBorderFrame
        self.imageBorderCornerRadius = imageBorderCornerRadius
        self.imageBorderCornerStyle = imageBorderCornerStyle
        self.isShowingTitle = isShowingTitle
        self.title = title
        self.isTitleLocalized = isTitleLocalized
        self.titleFont = titleFont
        self.titleTextCase = titleTextCase
        self.titleAlignment = titleAlignment
        self.titleLineSpacing = titleLineSpacing
        self.titleColor = titleColor
        self.titleGradientStart = titleGradientStart
        self.titleGradientEnd = titleGradientEnd
        self.isTitleColorGradient = isTitleColorGradient
        self.isReversed = isReversed
        self.alignment = alignment
        self.verticalAlignment = verticalAlignment
        self.horizontalAlignment = horizontalAlignment
        self.spacing = spacing
        self.verticalPadding = verticalPadding
        self.horizontalPadding = horizontalPadding
        self.maxHeight = maxHeight
        self.maxHeightAlignment = maxHeightAlignment
        self.isShowingBackground = isShowingBackground
        self.backgroundColor = backgroundColor
        self.backgroundGradientStart = backgroundGradientStart
        self.backgroundGradientEnd = backgroundGradientEnd
        self.isBackgroundColorGradient = isBackgroundColorGradient
        self.cornerRadius = cornerRadius
        self.cornerStyle = cornerStyle
        self.imageSingleTapAction = imageSingleTapAction
        self.imageDoubleTapAction = imageDoubleTapAction
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the border of the image should be shown at all:
    private var isShowingImageBorder: Bool {
        imageBorderWidth > 0
    }
    
    /// Gradient of the border of the image if applicable:
    private var imageBorderGradient: LinearGradient {
        .init(
            colors: [
                imageBorderGradientStart,
                imageBorderGradientEnd
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    /// Value of the alignment of the view that is based on the size of the dynamic type that is currently selected:
    private var alignmentValue: NT_Alignment {
        dynamicTypeSize >= .accessibility1 ? .vertical : alignment
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .contentBackground(
                verticalPadding: verticalPadding,
                horizontalPadding: horizontalPadding,
                maxHeight: maxHeight,
                maxHeightAlignment: maxHeightAlignment,
                isShowingBackground: isShowingBackground,
                backgroundColor: backgroundColor,
                backgroundGradientStart: backgroundGradientStart,
                backgroundGradientEnd: backgroundGradientEnd,
                isBackgroundColorGradient: isBackgroundColorGradient,
                cornerRadius: cornerRadius,
                cornerStyle: cornerStyle
            )
            .accessibilityElement(children: .combine)
    }
}

// MARK: - Item:

private extension ImageBackgroundBorderTitleView {
    @ViewBuilder
    private var item: some View {
        switch alignmentValue {
        case .horizontal: horizontalItem
        case .vertical: verticalItem
        }
    }
    
    private var horizontalItem: some View {
        HStack(
            alignment: verticalAlignment,
            spacing: spacing
        ) {
            itemContent
        }
    }
    
    private var verticalItem: some View {
        VStack(
            alignment: horizontalAlignment,
            spacing: spacing
        ) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        if isReversed {
            reversedItemContent
        } else {
            defaultItemContent
        }
    }
    
    @ViewBuilder
    private var reversedItemContent: some View {
        titleContent
        imageContent
    }
    
    @ViewBuilder
    private var defaultItemContent: some View {
        imageContent
        titleContent
    }
}

// MARK: - Image:

private extension ImageBackgroundBorderTitleView {
    private var imageContent: some View {
        ZStack {
            imageItem
        }
    }
    
    @ViewBuilder
    private var imageItem: some View {
        imageItemContent
        border
    }
    
    private var imageItemContent: some View {
        ImageBackgroundView(
            image: image,
            isResizable: isImageResizable,
            isClipped: isImageClipped,
            width: imageWidth,
            height: imageHeight,
            maxWidth: imageMaxWidth,
            alignment: imageAlignment,
            isFullWidth: isImageFullWidth,
            isShowingBackground: isShowingImageBackground,
            backgroundColor: imageBackgroundColor,
            backgroundGradientStart: imageBackgroundGradientStart,
            backgroundGradientEnd: imageBackgroundGradientEnd,
            isBackgroundColorGradient: isImageBackgroundColorGradient,
            cornerRadius: imageCornerRadius,
            cornerStyle: imageCornerStyle,
            accessibilityLabel: imageAccessibilityLabel,
            isAccessibilityLabelLocalized: isImageAccessibilityLabelLocalized,
            singleTapAction: imageSingleTapAction,
            doubleTapAction: imageDoubleTapAction
        )
    }
    
    @ViewBuilder
    private var border: some View {
        if isShowingImageBorder {
            borderContent
        }
    }
    
    private var borderContent: some View {
        borderItem
            .frame(
                width: imageBorderFrame,
                height: imageBorderFrame,
                alignment: .center
            )
    }
    
    @ViewBuilder
    private var borderItem: some View {
        if isImageBorderColorGradient {
            gradientBorderItemContent
        } else {
            borderItemContent
        }
    }
    
    private var gradientBorderItemContent: some View {
        RoundedRectangle(
            cornerRadius: imageBorderCornerRadius,
            style: imageBorderCornerStyle
        )
        .stroke(
            imageBorderGradient,
            lineWidth: imageBorderWidth
        )
    }
    
    private var borderItemContent: some View {
        RoundedRectangle(
            cornerRadius: imageBorderCornerRadius,
            style: imageBorderCornerStyle
        )
        .stroke(
            imageBorderColor,
            lineWidth: imageBorderWidth
        )
    }
}

// MARK: - Title:

private extension ImageBackgroundBorderTitleView {
    @ViewBuilder
    private var titleContent: some View {
        if isShowingTitle {
            titleItem
        }
    }
    
    private var titleItem: some View {
        titleItemContent
            .font(titleFont)
            .textCase(titleTextCase)
            .multilineTextAlignment(titleAlignment)
            .lineSpacing(titleLineSpacing)
            .foregroundGradient(
                color: titleColor,
                gradientStart: titleGradientStart,
                gradientEnd: titleGradientEnd,
                isGradient: isTitleColorGradient
            )
    }
    
    @ViewBuilder
    private var titleItemContent: some View {
        if isTitleLocalized {
            Text(.init(title))
        } else {
            Text(title)
        }
    }
}

// MARK: - Preview:

#Preview {
    ImageBackgroundBorderTitleView(
        image: .init(.main62),
        isImageResizable: true,
        isImageClipped: true,
        imageWidth: 56,
        imageHeight: 56,
        imageMaxWidth: nil,
        imageAlignment: .center,
        isImageFullWidth: false,
        isShowingImageBackground: false,
        imageBackgroundColor: .accent,
        imageBackgroundGradientStart: .blueGradientStart,
        imageBackgroundGradientEnd: .blueGradientEnd,
        isImageBackgroundColorGradient: false,
        imageCornerRadius: 28,
        imageCornerStyle: .continuous,
        imageAccessibilityLabel: "",
        isImageAccessibilityLabelLocalized: true,
        imageBorderWidth: 2,
        imageBorderColor: .init(.secondarySystemGroupedBackground),
        imageBorderGradientStart: .blueGradientStart,
        imageBorderGradientEnd: .blueGradientEnd,
        isImageBorderColorGradient: true,
        imageBorderFrame: 64,
        imageBorderCornerRadius: 32,
        imageBorderCornerStyle: .continuous,
        title: "Title",
        isTitleLocalized: true,
        titleFont: .caption2.bold(),
        titleTextCase: .none,
        titleAlignment: .center,
        titleLineSpacing: 0,
        titleColor: .primary,
        titleGradientStart: .blueGradientStart,
        titleGradientEnd: .blueGradientEnd,
        isTitleColorGradient: false,
        isReversed: false,
        alignment: .vertical,
        verticalAlignment: .top,
        horizontalAlignment: .center,
        spacing: 6,
        verticalPadding: 0,
        horizontalPadding: 0,
        maxHeight: nil,
        maxHeightAlignment: .topLeading,
        isShowingBackground: false,
        backgroundColor: .init(.secondarySystemGroupedBackground),
        backgroundGradientStart: .blueGradientStart,
        backgroundGradientEnd: .blueGradientEnd,
        isBackgroundColorGradient: false,
        cornerRadius: 0,
        cornerStyle: .continuous
    ) {
        
    } imageDoubleTapAction: {
        
    }
    .padding()
}
