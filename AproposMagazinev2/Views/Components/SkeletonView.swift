import SwiftUI
import Shimmer

// MARK: - Skeleton Loading Components

struct SkeletonView: View {
    let width: CGFloat?
    let height: CGFloat
    let cornerRadius: CGFloat
    
    init(width: CGFloat? = nil, height: CGFloat = 20, cornerRadius: CGFloat = 4) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.gray.opacity(0.2))
            .frame(width: width, height: height)
            .shimmering(
                active: true,
                animation: .linear(duration: 1.5).repeatForever(autoreverses: false),
                gradient: Gradient(colors: [
                    Color.clear,
                    Color.white.opacity(0.6),
                    Color.clear
                ])
            )
    }
}

// MARK: - Article Card Skeleton

struct ArticleCardSkeleton: View {
    let cardHeight: CGFloat
    let showStars: Bool
    
    init(cardHeight: CGFloat = 96, showStars: Bool = false) {
        self.cardHeight = cardHeight
        self.showStars = showStars
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Image skeleton
            SkeletonView(width: 80, height: cardHeight, cornerRadius: 8)
            
            VStack(alignment: .leading, spacing: 8) {
                // Title skeleton
                SkeletonView(width: nil, height: 16, cornerRadius: 4)
                
                // Subtitle skeleton
                SkeletonView(width: 0.7, height: 12, cornerRadius: 4)
                
                if showStars {
                    // Stars skeleton
                    HStack(spacing: 4) {
                        ForEach(0..<5) { _ in
                            SkeletonView(width: 12, height: 12, cornerRadius: 2)
                        }
                    }
                }
                
                Spacer()
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: cardHeight)
    }
}

// MARK: - Hero Card Skeleton

struct HeroCardSkeleton: View {
    let height: CGFloat
    
    init(height: CGFloat = 400) {
        self.height = height
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Hero image skeleton
            SkeletonView(width: nil, height: height, cornerRadius: 12)
            
            // Hero title skeleton
            VStack(alignment: .leading, spacing: 8) {
                SkeletonView(width: nil, height: 24, cornerRadius: 4)
                SkeletonView(width: 0.7, height: 16, cornerRadius: 4)
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - List Item Skeleton

struct ListItemSkeleton: View {
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Thumbnail skeleton
            SkeletonView(width: 100, height: 100, cornerRadius: 8)
            
            VStack(alignment: .leading, spacing: 6) {
                // Title skeleton
                SkeletonView(width: nil, height: 18, cornerRadius: 4)
                
                // Category skeleton
                SkeletonView(width: 0.6, height: 14, cornerRadius: 4)
                
                Spacer()
            }
            .frame(height: 100)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Section Skeleton

struct SectionSkeleton: View {
    let title: String
    let itemCount: Int
    let isHorizontal: Bool
    
    init(title: String, itemCount: Int = 6, isHorizontal: Bool = true) {
        self.title = title
        self.itemCount = itemCount
        self.isHorizontal = isHorizontal
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section title skeleton
            HStack {
                SkeletonView(width: 120, height: 25, cornerRadius: 4)
                Spacer()
                SkeletonView(width: 60, height: 16, cornerRadius: 4)
            }
            .padding(.horizontal, 16)
            
            if isHorizontal {
                // Horizontal scroll skeleton
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(0..<itemCount, id: \.self) { _ in
                            ArticleCardSkeleton(cardHeight: 96)
                                .frame(width: 173)
                        }
                    }
                    .padding(.leading, 16)
                }
                .frame(height: 120)
            } else {
                // Vertical list skeleton
                VStack(spacing: 8) {
                    ForEach(0..<itemCount, id: \.self) { _ in
                        ListItemSkeleton()
                    }
                }
            }
        }
    }
}

// MARK: - Full Page Skeleton

struct FullPageSkeleton: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Hero section skeleton
                HeroCardSkeleton(height: 300)
                
                // Sections skeleton
                SectionSkeleton(title: "Anbefalet", itemCount: 6)
                SectionSkeleton(title: "Anmeldelser", itemCount: 6)
                SectionSkeleton(title: "Populært", itemCount: 6)
                SectionSkeleton(title: "Musik", itemCount: 6)
                SectionSkeleton(title: "Kultur", itemCount: 6)
                SectionSkeleton(title: "Serier & Film", itemCount: 6)
                
                // All articles skeleton
                VStack(alignment: .leading, spacing: 16) {
                    SkeletonView(width: 120, height: 25, cornerRadius: 4)
                        .padding(.horizontal, 16)
                    
                    VStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { index in
                            ListItemSkeleton()
                            if index < 7 {
                                Divider()
                                    .padding(.leading, 16)
                            }
                        }
                    }
                    .background(Color("AppGray"))
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                }
                
                Spacer(minLength: 32)
            }
        }
    }
}

// MARK: - Custom Skeleton Animations

struct PulseSkeleton: View {
    let width: CGFloat?
    let height: CGFloat
    let cornerRadius: CGFloat
    
    @State private var isAnimating = false
    
    init(width: CGFloat? = nil, height: CGFloat = 20, cornerRadius: CGFloat = 4) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.gray.opacity(0.2))
            .frame(width: width, height: height)
            .opacity(isAnimating ? 0.3 : 0.8)
            .animation(
                .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

struct WaveSkeleton: View {
    let width: CGFloat?
    let height: CGFloat
    let cornerRadius: CGFloat
    
    @State private var phase: CGFloat = 0
    
    init(width: CGFloat? = nil, height: CGFloat = 20, cornerRadius: CGFloat = 4) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.gray.opacity(0.2),
                        Color.gray.opacity(0.4),
                        Color.gray.opacity(0.2)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: width, height: height)
            .mask(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black, location: 0.3),
                                .init(color: .black, location: 0.7),
                                .init(color: .clear, location: 1)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .offset(x: phase)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = width ?? 200
                }
            }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // Basic skeleton
        SkeletonView(width: 200, height: 20)
        
        // Article card skeleton
        ArticleCardSkeleton()
        
        // Hero card skeleton
        HeroCardSkeleton(height: 200)
        
        // List item skeleton
        ListItemSkeleton()
        
        // Pulse animation
        PulseSkeleton(width: 150, height: 20)
        
        // Wave animation
        WaveSkeleton(width: 150, height: 20)
    }
    .padding()
}