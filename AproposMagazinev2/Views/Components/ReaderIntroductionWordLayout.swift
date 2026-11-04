import SwiftUI

/// Text-sized controls flow naturally; words wider than the available row are
/// measured again with that width so accessibility text wraps without clipping.
struct ReaderIntroductionWordLayout: Layout {
    var spacing: CGFloat = 22
    var lineSpacing: CGFloat = 6

    private struct Item {
        let index: Int
        let size: CGSize
        let origin: CGPoint
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let width = finiteWidth(proposal.width, subviews: subviews)
        let items = arrange(width: width, subviews: subviews)
        return CGSize(width: width, height: items.map { $0.origin.y + $0.size.height }.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        for item in arrange(width: bounds.width, subviews: subviews) {
            subviews[item.index].place(at: CGPoint(x: bounds.minX + item.origin.x, y: bounds.minY + item.origin.y),
                anchor: .topLeading, proposal: ProposedViewSize(item.size))
        }
    }

    private func finiteWidth(_ proposed: CGFloat?, subviews: Subviews) -> CGFloat {
        if let proposed, proposed.isFinite { return max(0, proposed) }
        return subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Item] {
        var result: [Item] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for index in subviews.indices {
            let ideal = subviews[index].sizeThatFits(.unspecified)
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: min(ideal.width, width), height: nil))
            if x > 0, x + size.width > width {
                x = 0; y += rowHeight + lineSpacing; rowHeight = 0
            }
            result.append(Item(index: index, size: size, origin: CGPoint(x: x, y: y)))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return result
    }
}
