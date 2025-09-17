import SwiftUI

struct RatingView: View {
    let stars: Int
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<stars, id: \.self) { _ in
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                    .font(.caption)
            }
        }
    }
} 