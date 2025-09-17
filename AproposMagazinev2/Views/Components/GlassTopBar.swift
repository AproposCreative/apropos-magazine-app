import SwiftUI

struct GlassTopBar: View {
    let title: String?
    let showBackButton: Bool
    let showActionButtons: Bool
    let onBack: (() -> Void)?
    let onPlus: (() -> Void)?
    let onDownload: (() -> Void)?
    let onShare: (() -> Void)?
    
    init(
        title: String? = nil,
        showBackButton: Bool = true,
        showActionButtons: Bool = true,
        onBack: (() -> Void)? = nil,
        onPlus: (() -> Void)? = nil,
        onDownload: (() -> Void)? = nil,
        onShare: (() -> Void)? = nil
    ) {
        self.title = title
        self.showBackButton = showBackButton
        self.showActionButtons = showActionButtons
        self.onBack = onBack
        self.onPlus = onPlus
        self.onDownload = onDownload
        self.onShare = onShare
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                // Back button
                if showBackButton {
                    Button(action: {
                        onBack?()
                    }) {
                        Image(systemName: "chevron.left")
                            .foregroundColor(.white)
                            .font(.title3)
                            .frame(width: 32, height: 32)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                
                Spacer()
                
                // Title (if provided)
                if let title = title {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.white)
                        .fontWeight(.semibold)
                }
                
                Spacer()
                
                // Action buttons
                if showActionButtons {
                    HStack(spacing: 12) {
                        // Plus button
                        if onPlus != nil {
                            Button(action: {
                                onPlus?()
                            }) {
                                Image(systemName: "plus")
                                    .foregroundColor(.white)
                                    .font(.title3)
                                    .frame(width: 32, height: 32)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                        }
                        
                        // Download button
                        if onDownload != nil {
                            Button(action: {
                                onDownload?()
                            }) {
                                Image(systemName: "arrow.down")
                                    .foregroundColor(.white)
                                    .font(.title3)
                                    .frame(width: 32, height: 32)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                        }
                        
                        // Share button
                        if onShare != nil {
                            Button(action: {
                                onShare?()
                            }) {
                                Image(systemName: "arrow.up")
                                    .foregroundColor(.white)
                                    .font(.title3)
                                    .frame(width: 32, height: 32)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 50) // Status bar spacing
            .padding(.bottom, 10)
            .background(.ultraThinMaterial)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
        .ignoresSafeArea(.container, edges: .top)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack {
            GlassTopBar(
                title: "Søg",
                onBack: { print("Back tapped") },
                onPlus: { print("Plus tapped") },
                onDownload: { print("Download tapped") },
                onShare: { print("Share tapped") }
            )
            
            Spacer()
        }
    }
}
