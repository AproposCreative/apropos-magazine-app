//
//  SubtitleTitleImageBackgroundView.swift
//  Native
//

import SwiftUI

struct SubtitleTitleImageBackgroundView: View {
    
    // MARK: - Private properties:
    
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
    
    /// Color of the subtitle:
    private let subtitleColor: Color
    
    /// Starting color of the gradient of the subtitle if applicable:
    private let subtitleGradientStart: Color
    
    /// Ending color of the gradient of the subtitle if applicable:
    private let subtitleGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the subtitle should have a gradient applied to it:
    private let isSubtitleColorGradient: Bool
    
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
    
    /// Alignment of the subtitle and the title:
    private let subtitleTitleAlignment: HorizontalAlignment
    
    /// Spacing between the subtitle and the title:
    private let subtitleTitleSpacing: Double
    
    /// Maximum width of the subtitle and the title:
    private let subtitleTitleMaxWidth: CGFloat?
    
    /// Alignment of the subtitle and the title if they have a maximum width applied to it:
    private let subtitleTitleMaxWidthAlignment: Alignment
    
    /// Vertical padding around the subtitle and the title:
    private let subtitleTitleVerticalPadding: Double
    
    /// Horizontal padding around the subtitle and the title:
    private let subtitleTitleHorizontalPadding: Double
    
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
    
    /// Color of the shadow of the view if applicable:
    private let shadowColor: Color
    
    /// Radius of the shadow of the view if applicable:
    private let shadowRadius: Double
    
    /// X-axis position of the shadow of the view if applicable:
    private let shadowXAxis: Double
    
    /// Y-axis position of the shadow of the view if applicable:
    private let shadowYAxis: Double
    
    /// Alignment of the content of the view:
    private let alignment: Alignment
    
    /// 'Bool' value indicating whether or not the view should have a dark color scheme applied to it:
    private let isDarkColorScheme: Bool
    
    /// Action of the image after single tapping on it if applicable:
    private let imageSingleTapAction: (() -> ())?
    
    /// Action of the image after double tapping on it if applicable:
    private let imageDoubleTapAction: (() -> ())?
    
    init(
        isShowingSubtitle: Bool = true,
        subtitle: String,
        isSubtitleLocalized: Bool = true,
        subtitleFont: Font = .headline.weight(.bold),
        subtitleTextCase: Text.Case? = .uppercase,
        subtitleAlignment: TextAlignment = .leading,
        subtitleLineSpacing: Double = 0,
        subtitleColor: Color = .secondary,
        subtitleGradientStart: Color = .blueGradientStart,
        subtitleGradientEnd: Color = .blueGradientEnd,
        isSubtitleColorGradient: Bool = false,
        isShowingTitle: Bool = true,
        title: String,
        isTitleLocalized: Bool = true,
        titleFont: Font = .title.bold(),
        titleTextCase: Text.Case? = .none,
        titleAlignment: TextAlignment = .leading,
        titleLineSpacing: Double = 0,
        titleColor: Color = .primary,
        titleGradientStart: Color = .blueGradientStart,
        titleGradientEnd: Color = .blueGradientEnd,
        isTitleColorGradient: Bool = false,
        subtitleTitleAlignment: HorizontalAlignment = .leading,
        subtitleTitleSpacing: Double = 4,
        subtitleTitleMaxWidth: CGFloat? = nil,
        subtitleTitleMaxWidthAlignment: Alignment = .leading,
        subtitleTitleVerticalPadding: Double = 24,
        subtitleTitleHorizontalPadding: Double = 24,
        image: Image,
        isImageResizable: Bool = true,
        isImageClipped: Bool = true,
        imageWidth: CGFloat? = 304,
        imageHeight: CGFloat? = 400,
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
        shadowColor: Color = .black.opacity(0.12),
        shadowRadius: Double = 64,
        shadowXAxis: Double = 0,
        shadowYAxis: Double = 0,
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
        self.titleColor = titleColor
        self.titleGradientStart = titleGradientStart
        self.titleGradientEnd = titleGradientEnd
        self.isTitleColorGradient = isTitleColorGradient
        self.isShowingSubtitle = isShowingSubtitle
        self.subtitle = subtitle
        self.isSubtitleLocalized = isSubtitleLocalized
        self.subtitleFont = subtitleFont
        self.subtitleTextCase = subtitleTextCase
        self.subtitleAlignment = subtitleAlignment
        self.subtitleLineSpacing = subtitleLineSpacing
        self.subtitleColor = subtitleColor
        self.subtitleGradientStart = subtitleGradientStart
        self.subtitleGradientEnd = subtitleGradientEnd
        self.isSubtitleColorGradient = isSubtitleColorGradient
        self.subtitleTitleAlignment = subtitleTitleAlignment
        self.subtitleTitleSpacing = subtitleTitleSpacing
        self.subtitleTitleMaxWidth = subtitleTitleMaxWidth
        self.subtitleTitleMaxWidthAlignment = subtitleTitleMaxWidthAlignment
        self.subtitleTitleVerticalPadding = subtitleTitleVerticalPadding
        self.subtitleTitleHorizontalPadding = subtitleTitleHorizontalPadding
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
        self.shadowColor = shadowColor
        self.shadowRadius = shadowRadius
        self.shadowXAxis = shadowXAxis
        self.shadowYAxis = shadowYAxis
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
            .shadow(
                color: shadowColor,
                radius: shadowRadius,
                x: shadowXAxis,
                y: shadowYAxis
            )
            .accessibilityElement(children: .combine)
            .darkColorScheme(isDark: isDarkColorScheme)
    }
}

// MARK: - Item:

private extension SubtitleTitleImageBackgroundView {
    private var item: some View {
        ZStack(alignment: alignment) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        imageContent
        imageOverlay
        subtitleTitle
    }
}

// MARK: - Subtitle and title:

private extension SubtitleTitleImageBackgroundView {
    private var subtitleTitle: some View {
        subtitleTitleContent
            .padding(
                .vertical,
                subtitleTitleVerticalPadding
            )
            .padding(
                .horizontal,
                subtitleTitleHorizontalPadding
            )
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
    }
    
    private var subtitleTitleContent: some View {
        VStack(
            alignment: .leading,
            spacing: subtitleTitleSpacing
        ) {
            subtitleTitleItem
        }
    }
    
    @ViewBuilder
    private var subtitleTitleItem: some View {
        subtitleContent
        titleContent
    }
}

// MARK: - Subtitle:

private extension SubtitleTitleImageBackgroundView {
    @ViewBuilder
    private var subtitleContent: some View {
        if isShowingSubtitle {
            subtitleItem
        }
    }
    
    private var subtitleItem: some View {
        subtitleItemContent
            .font(subtitleFont)
            .textCase(subtitleTextCase)
            .multilineTextAlignment(subtitleAlignment)
            .lineSpacing(subtitleLineSpacing)
            .foregroundGradient(
                color: subtitleColor,
                gradientStart: subtitleGradientStart,
                gradientEnd: subtitleGradientEnd,
                isGradient: isSubtitleColorGradient
            )
    }
    
    @ViewBuilder
    private var subtitleItemContent: some View {
        if isSubtitleLocalized {
            Text(.init(subtitle))
        } else {
            Text(subtitle)
        }
    }
}

// MARK: - Title:

private extension SubtitleTitleImageBackgroundView {
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

// MARK: - Image:

private extension SubtitleTitleImageBackgroundView {
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
        SubtitleTitleImageBackgroundView(
            isShowingSubtitle: true,
            subtitle: "Subtitle",
            isSubtitleLocalized: true,
            subtitleFont: .headline.weight(.bold),
            subtitleTextCase: .uppercase,
            subtitleAlignment: .leading,
            subtitleLineSpacing: 0,
            subtitleColor: .secondary,
            subtitleGradientStart: .blueGradientStart,
            subtitleGradientEnd: .blueGradientEnd,
            isSubtitleColorGradient: false,
            isShowingTitle: true,
            title: "Title",
            isTitleLocalized: true,
            titleFont: .title.bold(),
            titleTextCase: .none,
            titleAlignment: .leading,
            titleLineSpacing: 0,
            titleColor: .primary,
            titleGradientStart: .blueGradientStart,
            titleGradientEnd: .blueGradientEnd,
            isTitleColorGradient: false,
            subtitleTitleAlignment: .leading,
            subtitleTitleSpacing: 4,
            subtitleTitleMaxWidth: nil,
            subtitleTitleMaxWidthAlignment: .leading,
            subtitleTitleVerticalPadding: 24,
            subtitleTitleHorizontalPadding: 24,
            image: .init(.main41),
            isImageResizable: true,
            isImageClipped: true,
            imageWidth: 304,
            imageHeight: 400,
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
            shadowColor: .black.opacity(0.12),
            shadowRadius: 64,
            shadowXAxis: 0,
            shadowYAxis: 0,
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
