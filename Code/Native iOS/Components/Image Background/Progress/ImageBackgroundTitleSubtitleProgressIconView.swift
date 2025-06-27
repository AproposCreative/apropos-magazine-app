//
//  ImageBackgroundTitleSubtitleProgressIconView.swift
//  Native
//

import SwiftUI

struct ImageBackgroundTitleSubtitleProgressIconView: View {
    
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
    
    /// Width of the border of the image:
    private let imageBorderWidth: Double
    
    /// Color of the border of the image:
    private let imageBorderColor: Color
    
    /// Accessibility label of the image:
    private let imageAccessibilityLabel: String
    
    /// 'Bool' value indicating whether or not the accessibility label of the image should be localized:
    private let isImageAccessibilityLabelLocalized: Bool
    
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
    
    /// Starting color of the gradient of the title if applicable:
    private let titleGradientStart: Color
    
    /// Ending color of the gradient of the title if applicable:
    private let titleGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the title should have a gradient applied to it:
    private let isTitleColorGradient: Bool
    
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
    
    /// Starting color of the gradient of the subtitle if applicable:
    private let subtitleGradientStart: Color
    
    /// Ending color of the gradient of the subtitle if applicable:
    private let subtitleGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the subtitle should have a gradient applied to it:
    private let isSubtitleColorGradient: Bool
    
    /// Alignment of the title and the subtitle:
    private let titleSubtitleAlignment: HorizontalAlignment
    
    /// Spacing between the title and the subtitle:
    private let titleSubtitleSpacing: Double
    
    /// Maximum width of the title and the subtitle:
    private let titleSubtitleMaxWidth: CGFloat?
    
    /// Alignment of the title and the subtitle if they have a maximum width applied to them:
    private let titleSubtitleMaxWidthAlignment: Alignment
    
    /// 'Bool' value indicating whether or not the progress bar should be shown at all:
    private let isShowingProgress: Bool
    
    /// Current value of the progress bar:
    private let progressValue: Double
    
    /// Total possible value of the progress bar:
    private let progressTotal: Double
    
    /// 'Bool' value indicating whether or not the title of the current value of the progress bar should be shown at all:
    private let isShowingProgressValueTitle: Bool
    
    /// An actual title of the current value of the progress bar to display if applicable:
    private let progressValueTitle: String?
    
    /// 'Bool' value indicating whether or not the title of the current value of the progress bar should be localized:
    private let isProgressValueTitleLocalized: Bool
    
    /// Font of the title of the current value of the progress bar:
    private let progressValueTitleFont: Font
    
    /// Text case of the title of the current value of the progress bar:
    private let progressValueTitleTextCase: Text.Case?
    
    /// Alignment of the title of the current value of the progress bar:
    private let progressValueTitleAlignment: TextAlignment
    
    /// Additional spacing between the multiple lines of the title of the current value of the progress bar:
    private let progressValueTitleLineSpacing: Double
    
    /// Color of the title of the current value of the progress bar:
    private let progressValueTitleColor: Color?
    
    /// Color of the progress bar:
    private let progressColor: Color
    
    /// Alignment of the title, subtitle, and the progress:
    private let titleSubtitleProgressAlignment: HorizontalAlignment
    
    /// Spacing between the title, subtitle, and the progress:
    private let titleSubtitleProgressSpacing: Double
    
    /// 'Bool' value indicating whether or not the icon should be shown at all:
    private let isShowingIcon: Bool
    
    /// An actual icon to display if applicable:
    private let icon: String
    
    /// Symbol variant of the icon if applicable (It could be '.fill', '.circle', etc.):
    private let iconSymbolVariant: SymbolVariants
    
    /// Font of the icon if applicable:
    private let iconFont: Font
    
    /// Color of the icon if applicable:
    private let iconColor: Color
    
    /// Starting color of the gradient of the icon if applicable:
    private let iconGradientStart: Color
    
    /// Ending color of the gradient of the icon if applicable:
    private let iconGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the icon should have a gradient applied to it if applicable:
    private let isIconColorGradient: Bool
    
    /// Size of the frame of the icon if applicable:
    private let iconFrame: CGFloat?
    
    /// Alignment of the title, subtitle, progress, and the icon:
    private let titleSubtitleProgressIconAlignment: VerticalAlignment
    
    /// Spacing between the title, subtitle, progress, and the icon:
    private let titleSubtitleProgressIconSpacing: Double
    
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
        imageWidth: CGFloat? = 48,
        imageHeight: CGFloat? = 48,
        imageMaxWidth: CGFloat? = nil,
        imageAlignment: Alignment = .center,
        isImageFullWidth: Bool = false,
        isShowingImageBackground: Bool = false,
        imageBackgroundColor: Color = .accent,
        imageBackgroundGradientStart: Color = .blueGradientStart,
        imageBackgroundGradientEnd: Color = .blueGradientEnd,
        isImageBackgroundColorGradient: Bool = true,
        imageCornerRadius: Double = 12,
        imageCornerStyle: RoundedCornerStyle = .continuous,
        imageBorderWidth: Double = 0,
        imageBorderColor: Color = .init(.secondarySystemGroupedBackground),
        imageAccessibilityLabel: String = "",
        isImageAccessibilityLabelLocalized: Bool = true,
        isShowingTitle: Bool = true,
        title: String,
        isTitleLocalized: Bool = true,
        titleFont: Font = .headline,
        titleTextCase: Text.Case? = .none,
        titleAlignment: TextAlignment = .leading,
        titleLineSpacing: Double = 0,
        titleLineLimit: Int? = nil,
        titleColor: Color = .primary,
        titleGradientStart: Color = .blueGradientStart,
        titleGradientEnd: Color = .blueGradientEnd,
        isTitleColorGradient: Bool = false,
        isShowingSubtitle: Bool = true,
        subtitle: String,
        isSubtitleLocalized: Bool = true,
        subtitleFont: Font = .subheadline,
        subtitleTextCase: Text.Case? = .none,
        subtitleAlignment: TextAlignment = .leading,
        subtitleLineSpacing: Double = 0,
        subtitleLineLimit: Int? = nil,
        subtitleColor: Color = .secondary,
        subtitleGradientStart: Color = .blueGradientStart,
        subtitleGradientEnd: Color = .blueGradientEnd,
        isSubtitleColorGradient: Bool = false,
        titleSubtitleAlignment: HorizontalAlignment = .leading,
        titleSubtitleSpacing: Double = 4,
        titleSubtitleMaxWidth: CGFloat? = .infinity,
        titleSubtitleMaxWidthAlignment: Alignment = .leading,
        isShowingProgress: Bool = true,
        progressValue: Double,
        progressTotal: Double,
        isShowingProgressValueTitle: Bool = false,
        progressValueTitle: String? = nil,
        isProgressValueTitleLocalized: Bool = false,
        progressValueTitleFont: Font = .footnote,
        progressValueTitleTextCase: Text.Case? = .none,
        progressValueTitleAlignment: TextAlignment = .leading,
        progressValueTitleLineSpacing: Double = 0,
        progressValueTitleColor: Color? = .secondary,
        progressColor: Color = .accent,
        titleSubtitleProgressAlignment: HorizontalAlignment = .leading,
        titleSubtitleProgressSpacing: Double = 8,
        isShowingIcon: Bool = true,
        icon: String = Icons.chevronRight,
        iconSymbolVariant: SymbolVariants = .none,
        iconFont: Font = .footnote.bold(),
        iconColor: Color = .init(.tertiaryLabel),
        iconGradientStart: Color = .blueGradientStart,
        iconGradientEnd: Color = .blueGradientEnd,
        isIconColorGradient: Bool = false,
        iconFrame: CGFloat? = 22,
        titleSubtitleProgressIconAlignment: VerticalAlignment = .top,
        titleSubtitleProgressIconSpacing: Double = 4,
        alignment: NT_Alignment = .horizontal,
        verticalAlignment: VerticalAlignment = .center,
        horizontalAlignment: HorizontalAlignment = .leading,
        spacing: Double = 12,
        verticalPadding: Double = 12,
        horizontalPadding: Double = 12,
        maxHeight: CGFloat? = nil,
        maxHeightAlignment: Alignment = .topLeading,
        isShowingBackground: Bool = true,
        backgroundColor: Color = .init(.secondarySystemGroupedBackground),
        backgroundGradientStart: Color = .blueGradientStart,
        backgroundGradientEnd: Color = .blueGradientEnd,
        isBackgroundColorGradient: Bool = false,
        cornerRadius: Double = 16,
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
        self.imageBorderWidth = imageBorderWidth
        self.imageBorderColor = imageBorderColor
        self.imageAccessibilityLabel = imageAccessibilityLabel
        self.isImageAccessibilityLabelLocalized = isImageAccessibilityLabelLocalized
        self.isShowingTitle = isShowingTitle
        self.title = title
        self.isTitleLocalized = isTitleLocalized
        self.titleFont = titleFont
        self.titleTextCase = titleTextCase
        self.titleAlignment = titleAlignment
        self.titleLineSpacing = titleLineSpacing
        self.titleLineLimit = titleLineLimit
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
        self.subtitleLineLimit = subtitleLineLimit
        self.subtitleColor = subtitleColor
        self.subtitleGradientStart = subtitleGradientStart
        self.subtitleGradientEnd = subtitleGradientEnd
        self.isSubtitleColorGradient = isSubtitleColorGradient
        self.titleSubtitleAlignment = titleSubtitleAlignment
        self.titleSubtitleSpacing = titleSubtitleSpacing
        self.titleSubtitleMaxWidth = titleSubtitleMaxWidth
        self.titleSubtitleMaxWidthAlignment = titleSubtitleMaxWidthAlignment
        self.isShowingProgress = isShowingProgress
        self.progressValue = progressValue
        self.progressTotal = progressTotal
        self.isShowingProgressValueTitle = isShowingProgressValueTitle
        self.progressValueTitle = progressValueTitle
        self.isProgressValueTitleLocalized = isProgressValueTitleLocalized
        self.progressValueTitleFont = progressValueTitleFont
        self.progressValueTitleTextCase = progressValueTitleTextCase
        self.progressValueTitleAlignment = progressValueTitleAlignment
        self.progressValueTitleLineSpacing = progressValueTitleLineSpacing
        self.progressValueTitleColor = progressValueTitleColor
        self.progressColor = progressColor
        self.titleSubtitleProgressAlignment = titleSubtitleProgressAlignment
        self.titleSubtitleProgressSpacing = titleSubtitleProgressSpacing
        self.isShowingIcon = isShowingIcon
        self.icon = icon
        self.iconSymbolVariant = iconSymbolVariant
        self.iconFont = iconFont
        self.iconColor = iconColor
        self.iconGradientStart = iconGradientStart
        self.iconGradientEnd = iconGradientEnd
        self.isIconColorGradient = isIconColorGradient
        self.iconFrame = iconFrame
        self.titleSubtitleProgressIconAlignment = titleSubtitleProgressIconAlignment
        self.titleSubtitleProgressIconSpacing = titleSubtitleProgressIconSpacing
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
    
    /// Content of the title of the current value of the progress bar if applicable:
    private var progressValueTitleContent: Text {
        if let progressValueTitle {
            if isProgressValueTitleLocalized {
                return Text(.init(progressValueTitle))
            } else {
                return Text(progressValueTitle)
            }
        } else {
            return Text(progressValue.formatted(.percent))
        }
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

private extension ImageBackgroundTitleSubtitleProgressIconView {
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
            horizontalItemContent
        }
    }
    
    @ViewBuilder
    private var horizontalItemContent: some View {
        imageContent
        titleSubtitleProgressIcon
    }
    
    private var verticalItem: some View {
        VStack(
            alignment: horizontalAlignment,
            spacing: spacing
        ) {
            verticalItemContent
        }
    }
    
    @ViewBuilder
    private var verticalItemContent: some View {
        verticalItemHeader
        titleSubtitleProgress
    }
    
    private var verticalItemHeader: some View {
        HStack(
            alignment: titleSubtitleProgressIconAlignment,
            spacing: titleSubtitleProgressIconSpacing
        ) {
            verticalItemHeaderContent
        }
    }
    
    @ViewBuilder
    private var verticalItemHeaderContent: some View {
        verticalItemHeaderImage
        iconContent
    }
    
    private var verticalItemHeaderImage: some View {
        imageContent
            .frame(
                maxWidth: titleSubtitleMaxWidth,
                alignment: titleSubtitleMaxWidthAlignment
            )
    }
}

// MARK: - Image:

private extension ImageBackgroundTitleSubtitleProgressIconView {
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
}

// MARK: - Title, subtitle, progress, and icon:

private extension ImageBackgroundTitleSubtitleProgressIconView {
    private var titleSubtitleProgressIcon: some View {
        HStack(
            alignment: titleSubtitleProgressIconAlignment,
            spacing: titleSubtitleProgressIconSpacing
        ) {
            titleSubtitleProgressIconContent
        }
    }
    
    @ViewBuilder
    private var titleSubtitleProgressIconContent: some View {
        titleSubtitleProgress
        iconContent
    }
}

// MARK: - Title, subtitle, and progress:

private extension ImageBackgroundTitleSubtitleProgressIconView {
    private var titleSubtitleProgress: some View {
        VStack(
            alignment: titleSubtitleProgressAlignment,
            spacing: titleSubtitleProgressSpacing
        ) {
            titleSubtitleProgressContent
        }
    }
    
    @ViewBuilder
    private var titleSubtitleProgressContent: some View {
        titleSubtitle
        progress
    }
}

// MARK: - Title and subtitle:

private extension ImageBackgroundTitleSubtitleProgressIconView {
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
            titleGradientStart: titleGradientStart,
            titleGradientEnd: titleGradientEnd,
            isTitleColorGradient: isTitleColorGradient,
            isShowingSubtitle: isShowingSubtitle,
            subtitle: subtitle,
            isSubtitleLocalized: isSubtitleLocalized,
            subtitleFont: subtitleFont,
            subtitleTextCase: subtitleTextCase,
            subtitleAlignment: subtitleAlignment,
            subtitleLineSpacing: subtitleLineSpacing,
            subtitleLineLimit: subtitleLineLimit,
            subtitleColor: subtitleColor,
            subtitleGradientStart: subtitleGradientStart,
            subtitleGradientEnd: subtitleGradientEnd,
            isSubtitleColorGradient: isSubtitleColorGradient,
            alignment: titleSubtitleAlignment,
            spacing: titleSubtitleSpacing,
            maxWidth: titleSubtitleMaxWidth,
            maxWidthAlignment: titleSubtitleMaxWidthAlignment
        )
    }
}

// MARK: - Progress:

private extension ImageBackgroundTitleSubtitleProgressIconView {
    @ViewBuilder
    private var progress: some View {
        if isShowingProgress {
            progressContent
        }
    }
    
    private var progressContent: some View {
        progressItem
            .progressViewStyle(.linear)
            .tint(progressColor)
    }
    
    private var progressItem: some View {
        ProgressView(
            value: progressValue,
            total: progressTotal
        ) {
            
        } currentValueLabel: {
            progressValueTitleItem
        }
    }
    
    @ViewBuilder
    private var progressValueTitleItem: some View {
        if isShowingProgressValueTitle {
            progressValueTitleItemContent
        }
    }
    
    private var progressValueTitleItemContent: some View {
        progressValueTitleContent
            .font(progressValueTitleFont)
            .textCase(progressValueTitleTextCase)
            .multilineTextAlignment(progressValueTitleAlignment)
            .lineSpacing(progressValueTitleLineSpacing)
            .optionalForegroundStyle(progressValueTitleColor)
    }
}

// MARK: - Icon:

private extension ImageBackgroundTitleSubtitleProgressIconView {
    @ViewBuilder
    private var iconContent: some View {
        if isShowingIcon {
            iconItem
        }
    }
    
    private var iconItem: some View {
        Image(systemName: icon)
            .symbolVariant(iconSymbolVariant)
            .font(iconFont)
            .foregroundGradient(
                color: iconColor,
                gradientStart: iconGradientStart,
                gradientEnd: iconGradientEnd,
                isGradient: isIconColorGradient
            )
            .frame(
                width: iconFrame,
                height: iconFrame,
                alignment: .center
            )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        ImageBackgroundTitleSubtitleProgressIconView(
            image: .init(.main24),
            isImageResizable: true,
            isImageClipped: true,
            imageWidth: 48,
            imageHeight: 48,
            imageMaxWidth: nil,
            imageAlignment: .center,
            isImageFullWidth: false,
            isShowingImageBackground: false,
            imageBackgroundColor: .accent,
            imageBackgroundGradientStart: .blueGradientStart,
            imageBackgroundGradientEnd: .blueGradientEnd,
            isImageBackgroundColorGradient: true,
            imageCornerRadius: 12,
            imageCornerStyle: .continuous,
            imageBorderWidth: 0,
            imageBorderColor: .init(.secondarySystemGroupedBackground),
            imageAccessibilityLabel: "",
            isImageAccessibilityLabelLocalized: true,
            isShowingTitle: true,
            title: "Title",
            isTitleLocalized: true,
            titleFont: .headline,
            titleTextCase: .none,
            titleAlignment: .leading,
            titleLineSpacing: 0,
            titleLineLimit: nil,
            titleColor: .primary,
            titleGradientStart: .blueGradientStart,
            titleGradientEnd: .blueGradientEnd,
            isTitleColorGradient: false,
            isShowingSubtitle: true,
            subtitle: "Subtitle",
            isSubtitleLocalized: true,
            subtitleFont: .subheadline,
            subtitleTextCase: .none,
            subtitleAlignment: .leading,
            subtitleLineSpacing: 0,
            subtitleLineLimit: nil,
            subtitleColor: .secondary,
            subtitleGradientStart: .blueGradientStart,
            subtitleGradientEnd: .blueGradientEnd,
            isSubtitleColorGradient: false,
            titleSubtitleAlignment: .leading,
            titleSubtitleSpacing: 4,
            titleSubtitleMaxWidth: .infinity,
            titleSubtitleMaxWidthAlignment: .leading,
            isShowingProgress: true,
            progressValue: 0.5,
            progressTotal: 1.0,
            isShowingProgressValueTitle: false,
            progressValueTitle: nil,
            isProgressValueTitleLocalized: false,
            progressValueTitleFont: .footnote,
            progressValueTitleTextCase: .none,
            progressValueTitleAlignment: .leading,
            progressValueTitleLineSpacing: 0,
            progressValueTitleColor: .secondary,
            progressColor: .accent,
            titleSubtitleProgressAlignment: .leading,
            titleSubtitleProgressSpacing: 8,
            isShowingIcon: true,
            icon: Icons.chevronRight,
            iconSymbolVariant: .none,
            iconFont: .footnote.bold(),
            iconColor: .init(.tertiaryLabel),
            iconGradientStart: .blueGradientStart,
            iconGradientEnd: .blueGradientEnd,
            isIconColorGradient: false,
            iconFrame: 22,
            titleSubtitleProgressIconAlignment: .center,
            titleSubtitleProgressIconSpacing: 4,
            alignment: .horizontal,
            verticalAlignment: .top,
            horizontalAlignment: .leading,
            spacing: 12,
            verticalPadding: 12,
            horizontalPadding: 12,
            maxHeight: nil,
            maxHeightAlignment: .topLeading,
            isShowingBackground: true,
            backgroundColor: .init(.secondarySystemGroupedBackground),
            backgroundGradientStart: .blueGradientStart,
            backgroundGradientEnd: .blueGradientEnd,
            isBackgroundColorGradient: false,
            cornerRadius: 16,
            cornerStyle: .continuous
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
