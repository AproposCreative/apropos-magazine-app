//
//  ImagesView.swift
//  Native
//

import SwiftUI

struct ImagesView: View {
    
    // MARK: - Private properties:
    
    /// Image that is currently selected:
    @State private var selectedImage: NT_Image?
    
    /// An array of the images to display:
    private let images: [NT_Image]
    
    /// Height of the view:
    private let height: Double
    
    /// Radius of the rounded corners of the view:
    private let cornerRadius: Double
    
    /// Style of the rounded corners of the view:
    private let cornerStyle: RoundedCornerStyle
    
    /// Spacing between the content of the view:
    private let spacing: Double
    
    /// Maximum width of the view:
    private let maxWidth: CGFloat?
    
    /// Alignment of the view if it has a maximum width applied to it:
    private let maxWidthAlignment: Alignment
    
    /// 'Bool' value indicating whether or not the pagination should be shown at all:
    private let isShowingPagination: Bool
    
    /// Color of the pagination:
    private let paginationColor: Color
    
    /// Starting color of the gradient of the pagination if applicable:
    private let paginationGradientStart: Color
    
    /// Ending color of the gradient of the pagination if applicable:
    private let paginationGradientEnd: Color
    
    /// 'Bool' value indicating whether or not the color of the pagination should have a gradient applied to it:
    private let isPaginationColorGradient: Bool
    
    /// Size of the frame of the pagination:
    private let paginationFrame: Double
    
    /// Spacing between the pagination:
    private let paginationSpacing: Double
    
    /// Vertical padding around the pagination:
    private let paginationVerticalPadding: Double
    
    /// Horizontal padding around the pagination:
    private let paginationHorizontalPadding: Double
    
    /// Alignment of the pagination:
    private let paginationAlignment: Alignment
    
    /// 'Bool' value indicating whether or not the haptic feedback should be triggered after selecting the image:
    private let isSelectionHapticFeedbackEnabled: Bool
    
    init(
        images: [NT_Image],
        height: Double = 224,
        cornerRadius: Double = 16,
        cornerStyle: RoundedCornerStyle = .continuous,
        spacing: Double = 16,
        maxWidth: CGFloat? = nil,
        maxWidthAlignment: Alignment = .center,
        isShowingPagination: Bool = true,
        paginationColor: Color = .white,
        paginationGradientStart: Color = .blueGradientStart,
        paginationGradientEnd: Color = .blueGradientEnd,
        isPaginationColorGradient: Bool = false,
        paginationFrame: Double = 8,
        paginationSpacing: Double = 10,
        paginationVerticalPadding: Double = 12,
        paginationHorizontalPadding: Double = 12,
        paginationAlignment: Alignment = .bottom,
        isSelectionHapticFeedbackEnabled: Bool = true
    ) {
        
        /// Properties initialization:
        _selectedImage = State(initialValue: images.first)
        self.images = images
        self.height = height
        self.cornerRadius = cornerRadius
        self.cornerStyle = cornerStyle
        self.spacing = spacing
        self.maxWidth = maxWidth
        self.maxWidthAlignment = maxWidthAlignment
        self.isShowingPagination = isShowingPagination
        self.paginationColor = paginationColor
        self.paginationGradientStart = paginationGradientStart
        self.paginationGradientEnd = paginationGradientEnd
        self.isPaginationColorGradient = isPaginationColorGradient
        self.paginationFrame = paginationFrame
        self.paginationSpacing = paginationSpacing
        self.paginationVerticalPadding = paginationVerticalPadding
        self.paginationHorizontalPadding = paginationHorizontalPadding
        self.paginationAlignment = paginationAlignment
        self.isSelectionHapticFeedbackEnabled = isSelectionHapticFeedbackEnabled
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be shown at all:
    private var isShowing: Bool {
        !images.isEmpty
    }
    
    /// Accessibility value of the view that is based on the image that is currently selected:
    private var accessibilityValue: LocalizedStringKey {
        if let selectedImage {
            return "Image \(selectedImage.content) \((images.firstIndex(of: selectedImage) ?? 0) + 1) out of \(images.count)"
        } else {
            return "No image selected"
        }
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
        scroll
            .frame(
                maxWidth: maxWidth,
                alignment: maxWidthAlignment
            )
            .overlay(alignment: paginationAlignment) {
                pagination
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(accessibilityValue)
            .accessibilityAdjustableAction(accessibilityAdjustableAction)
            .animation(
                .default,
                value: selectedImage
            )
    }
}

// MARK: - Scroll:

private extension ImagesView {
    private var scroll: some View {
        scrollContent
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $selectedImage)
    }
    
    private var scrollContent: some View {
        ScrollView(.horizontal) {
            scrollItem
        }
    }
    
    private var scrollItem: some View {
        imagesContent
            .scrollTargetLayout()
    }
}

// MARK: - Images:

private extension ImagesView {
    private var imagesContent: some View {
        LazyHStack(
            alignment: .center,
            spacing: spacing
        ) {
            imagesItem
        }
    }
    
    private var imagesItem: some View {
        ForEach(
            images,
            content: image
        )
    }
    
    private func image(_ image: NT_Image) -> some View {
        content(image)
            .resizable()
            .scaledToFill()
            .frame(
                height: height,
                alignment: .center
            )
            .roundedCorners(
                cornerRadius: cornerRadius,
                cornerStyle: cornerStyle
            )
            .containerRelativeFrame(.horizontal)
            .id(image)
    }
}

// MARK: - Pagination:

private extension ImagesView {
    @ViewBuilder
    private var pagination: some View {
        if isShowingPagination {
            paginationContent
        }
    }
    
    private var paginationContent: some View {
        PaginationView(
            current: $selectedImage,
            all: images,
            color: paginationColor,
            gradientStart: paginationGradientStart,
            gradientEnd: paginationGradientEnd,
            isColorGradient: isPaginationColorGradient,
            frame: paginationFrame,
            spacing: paginationSpacing,
            verticalPadding: paginationVerticalPadding,
            horizontalPadding: paginationHorizontalPadding,
            isSelectionHapticFeedbackEnabled: isSelectionHapticFeedbackEnabled
        )
    }
}

// MARK: - Functions:

private extension ImagesView {
    
    // MARK: - Private functions:
    
    /// Returns the content of the given image to display:
    private func content(_ image: NT_Image) -> Image {
        .init(image.content)
    }
    
    /// An accessibility action to adjust the value of the view that is based on the given direction:
    private func accessibilityAdjustableAction(_ direction: AccessibilityAdjustmentDirection) {
        
        /// Firstly making sure that we have the index of the selected image:
        guard let selectedImage,
              let index: Int = images.firstIndex(of: selectedImage) else {
            
            /// If not, then simply returning out of this method:
            return
        }
        
        /// If yes, then switching on the direction to perform the right action:
        switch direction {
        case .increment:
            
            /// If it's an increment, then making sure that we can get the next image by enumerating an array of all of the images and adding one to an index of the selected image:
            if let nextImage: NT_Image = images.enumerated().first(
                where: {
                    $0.offset == index + 1
                }
            )?.element {
                
                /// If yes, then assigning the next image as the selected one:
                self.selectedImage = nextImage
            } else if let firstImage: NT_Image = images.first {
                
                /// If we can't get the next image, then simply assigning the first image as the selected one:
                self.selectedImage = firstImage
            }
        case .decrement:
            
            /// If it's a decrement, then making sure that we can get the next image by enumerating an array of all of the images and subtracting one from an index of the selected image:
            if let previousImage: NT_Image = images.enumerated().first(
                where: {
                    $0.offset == index - 1
                }
            )?.element {
                
                /// If yes, then assigning the previous image as the selected one:
                self.selectedImage = previousImage
            } else if let lastImage: NT_Image = images.last {
                
                /// If we can't get the previous image, then simply assigning the last image as the selected one:
                self.selectedImage = lastImage
            }
        @unknown default:
            
            /// If none of the above, then simply breaking:
            break
        }
    }
}

// MARK: - Preview:

#Preview {
    ScrollView {
        ImagesView(
            images: NT_Image.example,
            height: 224,
            cornerRadius: 16,
            cornerStyle: .continuous,
            spacing: 16,
            maxWidth: nil,
            maxWidthAlignment: .center,
            isShowingPagination: true,
            paginationColor: .white,
            paginationGradientStart: .blueGradientStart,
            paginationGradientEnd: .blueGradientEnd,
            isPaginationColorGradient: false,
            paginationFrame: 8,
            paginationSpacing: 10,
            paginationVerticalPadding: 12,
            paginationHorizontalPadding: 12,
            paginationAlignment: .bottom,
            isSelectionHapticFeedbackEnabled: true
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
