import SwiftUI

struct StarsView: View {
    var rating: CGFloat      // fx 1–6
    var maxRating: Int = 6

    var body: some View {
        let stars = HStack(spacing: 2) {
            ForEach(0..<maxRating, id: \.self) { _ in
                Image(systemName: "star.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
            }
        }
        stars
            .overlay(
                GeometryReader { g in
                    let width = rating / CGFloat(maxRating) * g.size.width
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .frame(width: width)
                            .foregroundColor(.yellow)
                    }
                }
                .mask(stars)
            )
            .foregroundColor(.gray.opacity(0.4))
    }
} 