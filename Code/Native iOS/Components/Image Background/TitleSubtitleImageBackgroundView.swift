//
//  TitleSubtitleImageBackgroundView.swift
//  Native
//

import SwiftUI

struct TitleSubtitleImageBackgroundView: View {
    
    // MARK: - Private properties:
    
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
    
    /// Maximum number of lines that the title can have if applicable:
    private let titleLineLimit: Int?
    
    /// Color of the title:
    private let titleColor: Color
    
    /// 'Bool' value indicating whether or not the subtitle should be shown at all:
    private let isShowingSubtitle: Bool
    
    /// An actual subtitle to display:
    private let subtitle: String
    
    /// 'Bool' value indicating whether or not the subtitle should be localized:
    private let isSubtitleLocalized: Bool
    
    /// Font of the subtitle:
    private let subtitleFont: Font
    
    /// Text case of the subtitle:
    private let subtitleTextCase: Text.Case?
    
    /// Alignment of the subtitle:
    private let subtitleAlignment: TextAlignment
    
    /// Additional spacing between the multiple lines of the subtitle:
    private let subtitleLineSpacing: Double
    
    /// Maximum number of lines that the subtitle can have if applicable:
    private let subtitleLineLimit: Int?
    
    /// Color of the subtitle:
    private let subtitleColor: Color
    
    /// Alignment of the title and the subtitle:
    private let titleSubtitleAlignment: HorizontalAlignment
    
    /// Spacing between the title and the subtitle:
    private let titleSubtitleSpacing: Double
    
    /// Maximum width of the title and the subtitle:
    private let titleSubtitleMaxWidth: CGFloat?
    
    /// Alignment of the title and the subtitle if they have a maximum width applied to it:
    private let titleSubtitleMaxWidthAlignment: Alignment
    
    /// Vertical padding around the title and the subtitle:
    private let titleSubtitleVerticalPadding: Double
    
    /// Horizontal padding around the title and the subtitle:
    private let titleSubtitleHorizontalPadding: Double
    
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
    
    /// Width of the border of the image:
    private let imageBorderWidth: Double
    
    /// Color of the border of the image:
    private let imageBorderColor: Color
    
    /// Accessibility label of the image:
    private let imageAccessibilityLabel: String
    
    /// 'Bool' value indicating whether or not the accessibility label of the image should be localized:
    private let isImageAccessibilityLabelLocalized: Bool
    
    /// 'Bool' value indicating whether or not the overlay of the image should be shown at all:
    private let isShowingImageOverlay: Bool
    
    /// Starting color of the gradient of the overlay of the image if applicable:
    private let imageOverlayGradientStart: Color
    
    /// Ending color of the gradient of the overlay of the image if applicable:
    private let imageOverlayGradientEnd: Color
    
    /// Alignment of the content of the view:
    private let alignment: Alignment
    
    /// 'Bool' value indicating whether or not the view should have a dark color scheme applied to it:
    private let isDarkColorScheme: Bool
    
    /// Action of the image after single tapping on it if applicable:
    private let imageSingleTapAction: (() -> ())?
    
    /// Action of the image after double tapping on it if applicable:
    private let imageDoubleTapAction: (() -> ())?
    
    init(
        isShowingTitle: Bool = true,
        title: String,
        isTitleLocalized: Bool = true,
        titleFont: Font = .headline,
        titleTextCase: Text.Case? = .none,
        titleAlignment: TextAlignment = .leading,
        titleLineSpacing: Double = 0,
        titleLineLimit: Int? = nil,
        titleColor: Color = .primary,
        isShowingSubtitle: Bool = true,
        subtitle: String,
        isSubtitleLocalized: Bool = true,
        subtitleFont: Font = .subheadline,
        subtitleTextCase: Text.Case? = .none,
        subtitleAlignment: TextAlignment = .leading,
        subtitleLineSpacing: Double = 0,
        subtitleLineLimit: Int? = nil,
        subtitleColor: Color = .secondary,
        titleSubtitleAlignment: HorizontalAlignment = .leading,
        titleSubtitleSpacing: Double = 4,
        titleSubtitleMaxWidth: CGFloat? = nil,
        titleSubtitleMaxWidthAlignment: Alignment = .leading,
        titleSubtitleVerticalPadding: Double = 12,
        titleSubtitleHorizontalPadding: Double = 12,
        image: Image,
        isImageResizable: Bool = true,
        isImageClipped: Bool = true,
        imageWidth: CGFloat? = 304,
        imageHeight: CGFloat? = 224,
        imageMaxWidth: CGFloat? = nil,
        imageAlignment: Alignment = .center,
        isImageFullWidth: Bool = true,
        isShowingImageBackground: Bool = false,
        imageBackgroundColor: Color = .accent,
        imageBackgroundGradientStart: Color = .blueGradientStart,
        imageBackgroundGradientEnd: Color = .blueGradientEnd,
        isImageBackgroundColorGradient: Bool = true,
        imageCornerRadius: Double = 16,
        imageCornerStyle: RoundedCornerStyle = .continuous,
        imageBorderWidth: Double = 0,
        imageBorderColor: Color = .init(.secondarySystemGroupedBackground),
        imageAccessibilityLabel: String = "",
        isImageAccessibilityLabelLocalized: Bool = true,
        isShowingImageOverlay: Bool = true,
        imageOverlayGradientStart: Color = .black.opacity(0),
        imageOverlayGradientEnd: Color = .black.opacity(0.48),
        alignment: Alignment = .bottomLeading,
        isDarkColorScheme: Bool = true,
        imageSingleTapAction: (() -> ())? = nil,
        imageDoubleTapAction: (() -> ())? = nil
    ) {
        
        /// Properties initialization:
        self.isShowingTitle = isShowingTitle
        self.title = title
        self.isTitleLocalized = isTitleLocalized
        self.titleFont = titleFont
        self.titleTextCase = titleTextCase
        self.titleAlignment = titleAlignment
        self.titleLineSpacing = titleLineSpacing
        self.titleLineLimit = titleLineLimit
        self.titleColor = titleColor
        self.isShowingSubtitle = isShowingSubtitle
        self.subtitle = subtitle
        self.isSubtitleLocalized = isSubtitleLocalized
        self.subtitleFont = subtitleFont
        self.subtitleTextCase = subtitleTextCase
        self.subtitleAlignment = subtitleAlignment
        self.subtitleLineSpacing = subtitleLineSpacing
        self.subtitleLineLimit = subtitleLineLimit
        self.subtitleColor = subtitleColor
        self.titleSubtitleAlignment = titleSubtitleAlignment
        self.titleSubtitleSpacing = titleSubtitleSpacing
        self.titleSubtitleMaxWidth = titleSubtitleMaxWidth
        self.titleSubtitleMaxWidthAlignment = titleSubtitleMaxWidthAlignment
        self.titleSubtitleVerticalPadding = titleSubtitleVerticalPadding
        self.titleSubtitleHorizontalPadding = titleSubtitleHorizontalPadding
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
        self.imageBorderWidth = imageBorderWidth
        self.imageBorderColor = imageBorderColor
        self.imageAccessibilityLabel = imageAccessibilityLabel
        self.isImageAccessibilityLabelLocalized = isImageAccessibilityLabelLocalized
        self.isShowingImageOverlay = isShowingImageOverlay
        self.imageOverlayGradientStart = imageOverlayGradientStart
        self.imageOverlayGradientEnd = imageOverlayGradientEnd
        self.alignment = alignment
        self.isDarkColorScheme = isDarkColorScheme
        self.imageSingleTapAction = imageSingleTapAction
        self.imageDoubleTapAction = imageDoubleTapAction
    }
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .accessibilityElement(children: .combine)
            .darkColorScheme(isDark: isDarkColorScheme)
    }
}

// MARK: - Item:

private extension TitleSubtitleImageBackgroundView {
    private var item: some View {
        ZStack(alignment: alignment) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        imageContent
        imageOverlay
        titleSubtitle
    }
}

// MARK: - Title and subtitle:

private extension TitleSubtitleImageBackgroundView {
    private var titleSubtitle: some View {
        TitleSubtitleView(
            isShowingTitle: isShowingTitle,
            title: title,
            isTitleLocalized: isTitleLocalized,
            titleFont: titleFont,
            titleTextCase: titleTextCase,
            titleAlignment: titleAlignment,
            titleLineSpacing: titleLineSpacing,
            titleLineLimit: titleLineLimit,
            titleColor: titleColor,
            isShowingSubtitle: isShowingSubtitle,
            subtitle: subtitle,
            isSubtitleLocalized: isSubtitleLocalized,
            subtitleFont: subtitleFont,
            subtitleTextCase: subtitleTextCase,
            subtitleAlignment: subtitleAlignment,
            subtitleLineSpacing: subtitleLineSpacing,
            subtitleLineLimit: subtitleLineLimit,
            subtitleColor: subtitleColor,
            alignment: titleSubtitleAlignment,
            spacing: titleSubtitleSpacing,
            maxWidth: titleSubtitleMaxWidth,
            maxWidthAlignment: titleSubtitleMaxWidthAlignment,
            verticalPadding: titleSubtitleVerticalPadding,
            horizontalPadding: titleSubtitleHorizontalPadding
        )
    }
}

// MARK: - Image:

private extension TitleSubtitleImageBackgroundView {
    private var imageContent: some View {
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
            borderWidth: imageBorderWidth,
            borderColor: imageBorderColor,
            accessibilityLabel: imageAccessibilityLabel,
            isAccessibilityLabelLocalized: isImageAccessibilityLabelLocalized,
            singleTapAction: imageSingleTapAction,
            doubleTapAction: imageDoubleTapAction
        )
    }
    
    @ViewBuilder
    private var imageOverlay: some View {
        if isShowingImageOverlay {
            imageOverlayContent
        }
    }
    
    private var imageOverlayContent: some View {
        imageOverlayItem
            .frame(
                height: imageHeight,
                alignment: .center
            )
            .roundedCorners(
                cornerRadius: imageCornerRadius,
                cornerStyle: imageCornerStyle
            )
    }
    
    private var imageOverlayItem: some View {
        LinearGradient(
            colors: [
                imageOverlayGradientStart,
                imageOverlayGradientEnd
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        TitleSubtitleImageBackgroundView(
            isShowingTitle: true,
            title: "Title",
            isTitleLocalized: true,
            titleFont: .headline,
            titleTextCase: .none,
            titleAlignment: .leading,
            titleLineSpacing: 0,
            titleLineLimit: nil,
            titleColor: .primary,
            isShowingSubtitle: true,
            subtitle: "Subtitle",
            isSubtitleLocalized: true,
            subtitleFont: .subheadline,
            subtitleTextCase: .none,
            subtitleAlignment: .leading,
            subtitleLineSpacing: 0,
            subtitleLineLimit: nil,
            subtitleColor: .secondary,
            titleSubtitleAlignment: .leading,
            titleSubtitleSpacing: 4,
            titleSubtitleMaxWidth: nil,
            titleSubtitleMaxWidthAlignment: .leading,
            titleSubtitleVerticalPadding: 12,
            titleSubtitleHorizontalPadding: 12,
            image: .init(.main21),
            isImageResizable: true,
            isImageClipped: true,
            imageWidth: 304,
            imageHeight: 224,
            imageMaxWidth: nil,
            imageAlignment: .center,
            isImageFullWidth: true,
            isShowingImageBackground: false,
            imageBackgroundColor: .accent,
            imageBackgroundGradientStart: .blueGradientStart,
            imageBackgroundGradientEnd: .blueGradientEnd,
            isImageBackgroundColorGradient: true,
            imageCornerRadius: 16,
            imageCornerStyle: .continuous,
            imageBorderWidth: 0,
            imageBorderColor: .init(.secondarySystemGroupedBackground),
            imageAccessibilityLabel: "",
            isImageAccessibilityLabelLocalized: true,
            isShowingImageOverlay: true,
            imageOverlayGradientStart: .black.opacity(0),
            imageOverlayGradientEnd: .black.opacity(0.48),
            alignment: .bottomLeading,
            isDarkColorScheme: true
        ) {
            
        } imageDoubleTapAction: {
            
        }
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
