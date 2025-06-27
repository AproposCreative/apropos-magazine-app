//
//  ImageTitleSubtitleRatingView.swift
//  Native
//

import SwiftUI

struct ImageTitleSubtitleRatingView: View {
    
    // MARK: - Private properties:
    
    /// Size of the dynamic type that is currently selected:
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    /// An actual image to display:
    private let image: Image
    
    /// Size of the frame of the image:
    private let imageFrame: Double
    
    /// Radius of the rounded corners of the image:
    private let imageCornerRadius: Double
    
    /// Style of the rounded corners of the image:
    private let imageCornerStyle: RoundedCornerStyle
    
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
    
    /// Alignment of the title and the subtitle if they have a maximum width applied to them:
    private let titleSubtitleMaxWidthAlignment: Alignment
    
    /// An actual rating to display:
    private let rating: Int
    
    /// Icon of the rating:
    private let ratingIcon: String
    
    /// Symbol variant of the icon of the rating:
    private let ratingIconSymbolVariant: SymbolVariants
    
    /// Font of the rating:
    private let ratingFont: Font
    
    /// Color of the rating:
    private let ratingColor: Color
    
    /// Starting color of the gradient of the color of the rating if applicable:
    private let ratingGradientStart: Color
    
    /// Ending color of the gradient of the color of the rating if applicable:
    private let ratingGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the rating should have a gradient applied to it:
    private let isRatingColorGradient: Bool
    
    /// Alignment of the rating:
    private let ratingAlignment: VerticalAlignment
    
    /// Spacing between the content of the rating:
    private let ratingSpacing: Double
    
    /// Alignment of the title, the subtitle, and the rating:
    private let titleSubtitleRatingAlignment: HorizontalAlignment
    
    /// Spacing between the title, the subtitle, and the rating:
    private let titleSubtitleRatingSpacing: Double
    
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
    
    /// Radius of the rounded corners of the background of the view:
    private let cornerRadius: Double
    
    /// Style of the rounded corners of the background of the view:
    private let cornerStyle: RoundedCornerStyle
    
    init(
        image: Image,
        imageFrame: Double = 48,
        imageCornerRadius: Double = 12,
        imageCornerStyle: RoundedCornerStyle = .continuous,
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
        titleSubtitleMaxWidth: CGFloat? = .infinity,
        titleSubtitleMaxWidthAlignment: Alignment = .leading,
        rating: Int,
        ratingIcon: String = Icons.star,
        ratingIconSymbolVariant: SymbolVariants = .fill,
        ratingFont: Font = .system(
            size: 15,
            weight: .regular,
            design: .default
        ),
        ratingColor: Color = .orange,
        ratingGradientStart: Color = .orangeGradientStart,
        ratingGradientEnd: Color = .orangeGradientEnd,
        isRatingColorGradient: Bool = true,
        ratingAlignment: VerticalAlignment = .top,
        ratingSpacing: Double = 4,
        titleSubtitleRatingAlignment: HorizontalAlignment = .leading,
        titleSubtitleRatingSpacing: Double = 4,
        alignment: NT_Alignment = .horizontal,
        verticalAlignment: VerticalAlignment = .top,
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
        cornerStyle: RoundedCornerStyle = .continuous
    ) {
        
        /// Properties initialization:
        self.image = image
        self.imageFrame = imageFrame
        self.imageCornerRadius = imageCornerRadius
        self.imageCornerStyle = imageCornerStyle
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
        self.rating = rating
        self.ratingIcon = ratingIcon
        self.ratingIconSymbolVariant = ratingIconSymbolVariant
        self.ratingFont = ratingFont
        self.ratingColor = ratingColor
        self.ratingGradientStart = ratingGradientStart
        self.ratingGradientEnd = ratingGradientEnd
        self.isRatingColorGradient = isRatingColorGradient
        self.ratingAlignment = ratingAlignment
        self.ratingSpacing = ratingSpacing
        self.titleSubtitleRatingAlignment = titleSubtitleRatingAlignment
        self.titleSubtitleRatingSpacing = titleSubtitleRatingSpacing
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
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the rating should be shown at all:
    private var isShowingRating: Bool {
        rating > 0
    }
    
    /// An actual rating to display:
    private var ratingItems: Range<Int> {
        0 ..< rating
    }
    
    /// 'Bool' value indicating whether or not the content of the view should be moved that is based on the size of the dynamic type that is currently selected:
    private var shouldMoveContent: Bool {
        dynamicTypeSize >= .accessibility1
    }
    
    /// Value of the alignment of the view that is based on the size of the dynamic type that is currently selected:
    private var alignmentValue: NT_Alignment {
        shouldMoveContent ? .vertical : alignment
    }
    
    /// Accessibility label of the rating that is needed for the VoiceOver:
    private var ratingAccessibilityLabel: LocalizedStringKey {
        "\(rating) star rating"
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

private extension ImageTitleSubtitleRatingView {
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
        imageContent
        titleSubtitleRating
    }
}

// MARK: - Image:

private extension ImageTitleSubtitleRatingView {
    private var imageContent: some View {
        image
            .resizable()
            .scaledToFill()
            .frame(
                width: imageFrame,
                height: imageFrame,
                alignment: .center
            )
            .roundedCorners(
                cornerRadius: imageCornerRadius,
                cornerStyle: imageCornerStyle
            )
    }
}

// MARK: - Title subtitle, and rating:

private extension ImageTitleSubtitleRatingView {
    private var titleSubtitleRating: some View {
        VStack(
            alignment: titleSubtitleRatingAlignment,
            spacing: titleSubtitleRatingSpacing
        ) {
            titleSubtitleRatingContent
        }
    }
    
    @ViewBuilder
    private var titleSubtitleRatingContent: some View {
        titleSubtitle
        ratingScroll
    }
}

// MARK: - Title and subtitle:

private extension ImageTitleSubtitleRatingView {
    private var titleSubtitle: some View {
        TitleSubtitleView(
            isShowingTitle: isShowingTitle,
            title: title,
            isTitleLocalized: isTitleLocalized,
            titleFont: titleFont,
            titleTextCase: titleTextCase,
            titleAlignment: titleAlignment,
            titleLineSpacing: titleLineSpacing,
            titleColor: titleColor,
            isShowingSubtitle: isShowingSubtitle,
            subtitle: subtitle,
            isSubtitleLocalized: isSubtitleLocalized,
            subtitleFont: subtitleFont,
            subtitleTextCase: subtitleTextCase,
            subtitleAlignment: subtitleAlignment,
            subtitleLineSpacing: subtitleLineSpacing,
            subtitleColor: subtitleColor,
            alignment: titleSubtitleAlignment,
            spacing: titleSubtitleSpacing,
            maxWidth: titleSubtitleMaxWidth,
            maxWidthAlignment: titleSubtitleMaxWidthAlignment
        )
    }
}

// MARK: - Rating:

private extension ImageTitleSubtitleRatingView {
    @ViewBuilder
    private var ratingScroll: some View {
        if isShowingRating {
            ratingScrollContent
        }
    }
    
    @ViewBuilder
    private var ratingScrollContent: some View {
        if shouldMoveContent {
            ratingScrollItem
        } else {
            ratingContent
        }
    }
    
    private var ratingScrollItem: some View {
        ratingScrollItemContent
            .scrollIndicators(.hidden)
    }
    
    private var ratingScrollItemContent: some View {
        ScrollView(.horizontal) {
            ratingContent
        }
    }
    
    private var ratingContent: some View {
        ratingItem
            .accessibilityElement(children: .combine)
            .accessibilityLabel(ratingAccessibilityLabel)
    }
    
    private var ratingItem: some View {
        HStack(
            alignment: ratingAlignment,
            spacing: ratingSpacing
        ) {
            ratingItemContent
        }
    }
    
    private var ratingItemContent: some View {
        ForEach(
            ratingItems,
            id: \.self,
            content: ratingIcon
        )
    }
    
    private func ratingIcon(_ rating: Int) -> some View {
        Image(systemName: ratingIcon)
            .symbolVariant(ratingIconSymbolVariant)
            .font(ratingFont)
            .foregroundGradient(
                color: ratingColor,
                gradientStart: ratingGradientStart,
                gradientEnd: ratingGradientEnd,
                isGradient: isRatingColorGradient
            )
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        ImageTitleSubtitleRatingView(
            image: .init(.paywall81),
            imageFrame: 48,
            imageCornerRadius: 8,
            imageCornerStyle: .continuous,
            isShowingTitle: true,
            title: "Title",
            isTitleLocalized: true,
            titleFont: .headline,
            titleTextCase: .none,
            titleAlignment: .leading,
            titleLineSpacing: 0,
            titleColor: .primary,
            isShowingSubtitle: true,
            subtitle: "Subtitle",
            isSubtitleLocalized: true,
            subtitleFont: .subheadline,
            subtitleTextCase: .none,
            subtitleAlignment: .leading,
            subtitleLineSpacing: 0,
            subtitleColor: .secondary,
            titleSubtitleAlignment: .leading,
            titleSubtitleSpacing: 4,
            rating: 5,
            ratingIcon: Icons.star,
            ratingIconSymbolVariant: .fill,
            ratingFont: .system(
                size: 15,
                weight: .regular,
                design: .default
            ),
            ratingColor: .yellow,
            ratingGradientStart: .yellow,
            ratingGradientEnd: .orange,
            isRatingColorGradient: true,
            ratingAlignment: .top,
            ratingSpacing: 4,
            titleSubtitleRatingAlignment: .leading,
            titleSubtitleRatingSpacing: 4,
            alignment: .horizontal,
            verticalAlignment: .top,
            horizontalAlignment: .leading,
            spacing: 8,
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
