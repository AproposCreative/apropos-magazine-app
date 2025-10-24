import SwiftUI
import SDWebImage
import SDWebImageSwiftUI

struct OptimizedImageView: View {
    let url: URL?
    let placeholder: String
    let contentMode: ContentMode
    let cornerRadius: CGFloat
    let showShimmer: Bool
    
    @State private var isLoading = true
    @State private var loadError = false
    
    init(
        url: URL?,
        placeholder: String = "photo",
        contentMode: ContentMode = .fill,
        cornerRadius: CGFloat = 0,
        showShimmer: Bool = true
    ) {
        self.url = url
        self.placeholder = placeholder
        self.contentMode = contentMode
        self.cornerRadius = cornerRadius
        self.showShimmer = showShimmer
    }
    
    var body: some View {
        Group {
            if let url = url {
                WebImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                } placeholder: {
                    if showShimmer {
                        SkeletonView(width: nil, height: 200, cornerRadius: cornerRadius)
                    } else {
                        placeholderView
                    }
                }
                .onFailure { error in
                    print("🖼️ Image loading failed: \(error.localizedDescription)")
                    loadError = true
                }
                .onAppear {
                    isLoading = true
                }
                // Cancel image loading and reset states when view disappears
                .onDisappear {
                    // Cancel ongoing image download to free memory and resources
                    SDWebImageManager.shared.cancelAll()
                    isLoading = false
                    loadError = false
                }
            } else {
                placeholderView
            }
        }
        .overlay(
            // Loading indicator
            Group {
                if isLoading && showShimmer {
                    SkeletonView(width: nil, height: 200, cornerRadius: cornerRadius)
                }
            }
        )
    }
    
    private var placeholderView: some View {
        Image(systemName: placeholder)
            .font(.largeTitle)
            .foregroundColor(.secondary.opacity(0.5))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Progressive Image Loading

struct ProgressiveImageView: View {
    let url: URL?
    let placeholder: String
    let contentMode: ContentMode
    let cornerRadius: CGFloat
    
    @State private var currentImage: UIImage?
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if let image = currentImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            } else {
                placeholderView
            }
        }
        .onAppear {
            loadProgressiveImage()
        }
        .onDisappear {
            // Cancel any ongoing image downloads to free up memory and network resources
            SDWebImageManager.shared.cancelAll()
            // Reset state to initial to avoid retaining images when view is offscreen
            currentImage = nil
            isLoading = false
        }
    }
    
    private func loadProgressiveImage() {
        guard let url = url else { return }
        
        isLoading = true
        
        SDWebImageManager.shared.loadImage(
            with: url,
            options: [.progressiveLoad, .refreshCached, .retryFailed],
            progress: { receivedSize, expectedSize, _ in
                // Progressive loading progress
                let progress = Float(receivedSize) / Float(expectedSize)
                if progress > 0.1 && self.currentImage == nil {
                    // Show low-quality image first
                    self.loadLowQualityImage(from: url)
                }
            }
        ) { image, _, error, _, _, _ in
            DispatchQueue.main.async {
                if let error = error {
                    print("🖼️ Progressive image loading failed: \(error.localizedDescription)")
                }
                self.currentImage = image
                self.isLoading = false
                if image != nil {
                    HapticManager.shared.lightImpact()
                }
            }
        }
    }
    
    private func loadLowQualityImage(from url: URL) {
        // Load a smaller version for progressive loading
        let lowQualityURL = url.appendingPathComponent("?w=200&q=30")
        
        SDWebImageManager.shared.loadImage(
            with: lowQualityURL,
            options: [.lowPriority, .retryFailed],
            progress: nil
        ) { image, _, error, _, _, _ in
            DispatchQueue.main.async {
                if let error = error {
                    print("🖼️ Low quality image loading failed: \(error.localizedDescription)")
                }
                if self.currentImage == nil {
                    self.currentImage = image
                }
            }
        }
    }
    
    private var placeholderView: some View {
        Image(systemName: placeholder)
            .font(.largeTitle)
            .foregroundColor(.secondary.opacity(0.5))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Responsive Image Loading

struct ResponsiveImageView: View {
    let baseURL: URL?
    let placeholder: String
    let contentMode: ContentMode
    let cornerRadius: CGFloat
    
    @Environment(\.displayScale) private var displayScale
    
    private var optimizedURL: URL? {
        guard let baseURL = baseURL else { return nil }
        
        // Calculate optimal size based on display scale
        let scale = Int(displayScale)
        let width = 400 * scale // Base width * scale
        
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "w", value: "\(width)"),
            URLQueryItem(name: "q", value: "85"),
            // Remove WEBP format to avoid loading errors - use default format instead
            // URLQueryItem(name: "fmt", value: "webp")
        ]
        
        return components?.url
    }
    
    var body: some View {
        OptimizedImageView(
            url: optimizedURL,
            placeholder: placeholder,
            contentMode: contentMode,
            cornerRadius: cornerRadius
        )
        // Cancel downloads and cleanup when disappearing
        .onDisappear {
            SDWebImageManager.shared.cancelAll()
        }
    }
}

// MARK: - Image Cache Management

struct ImageCacheStatusView: View {
    @ObservedObject private var cacheManager = CacheManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "photo.on.rectangle")
                    .foregroundColor(.blue)
                
                Text("Billede cache")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text(cacheManager.cacheSize)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if cacheManager.isClearingCache {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Rydder cache...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Image Preloading

struct ImagePreloader {
    static func preloadImages(for articles: [Article]) {
        let urls = articles.compactMap { article in
            var mutableArticle = article
            let thumbnailURL = mutableArticle.thumbnailURL
            return URL(string: thumbnailURL)
        }
        
        DispatchQueue.global(qos: .utility).async {
            for url in urls.prefix(10) { // Preload first 10 images
                SDWebImageManager.shared.loadImage(
                    with: url,
                    options: [.preloadAllFrames, .refreshCached, .retryFailed],
                    progress: nil
                ) { _, _, error, _, _, _ in
                    if let error = error {
                        print("🖼️ Image preload failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    static func preloadImage(_ url: URL) {
        SDWebImageManager.shared.loadImage(
            with: url,
            options: [.preloadAllFrames],
            progress: nil
        ) { _, _, _, _, _, _ in }
    }
}

// MARK: - SwiftUI Extensions

extension View {
    func optimizedImage(
        _ url: URL?,
        placeholder: String = "photo",
        contentMode: ContentMode = .fill,
        cornerRadius: CGFloat = 0
    ) -> some View {
        OptimizedImageView(
            url: url,
            placeholder: placeholder,
            contentMode: contentMode,
            cornerRadius: cornerRadius
        )
        .onDisappear {
            // Cancel any ongoing image downloads to improve memory usage
            SDWebImageManager.shared.cancelAll()
        }
    }
    
    func progressiveImage(
        _ url: URL?,
        placeholder: String = "photo",
        contentMode: ContentMode = .fill,
        cornerRadius: CGFloat = 0
    ) -> some View {
        ProgressiveImageView(
            url: url,
            placeholder: placeholder,
            contentMode: contentMode,
            cornerRadius: cornerRadius
        )
        .onDisappear {
            // Cancel ongoing downloads and reset states to avoid memory leaks
            SDWebImageManager.shared.cancelAll()
        }
    }
    
    func responsiveImage(
        _ url: URL?,
        placeholder: String = "photo",
        contentMode: ContentMode = .fill,
        cornerRadius: CGFloat = 0
    ) -> some View {
        ResponsiveImageView(
            baseURL: url,
            placeholder: placeholder,
            contentMode: contentMode,
            cornerRadius: cornerRadius
        )
        .onDisappear {
            // Cancel downloads for resource cleanup
            SDWebImageManager.shared.cancelAll()
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        OptimizedImageView(
            url: URL(string: "https://picsum.photos/400/300"),
            cornerRadius: 12
        )
        .frame(height: 200)
        
        ProgressiveImageView(
            url: URL(string: "https://picsum.photos/400/300"),
            placeholder: "photo",
            contentMode: .fill,
            cornerRadius: 12
        )
        .frame(height: 200)
        
        ResponsiveImageView(
            baseURL: URL(string: "https://picsum.photos/400/300"),
            placeholder: "photo",
            contentMode: .fill,
            cornerRadius: 12
        )
        .frame(height: 200)
        
        ImageCacheStatusView()
    }
    .padding()
}
