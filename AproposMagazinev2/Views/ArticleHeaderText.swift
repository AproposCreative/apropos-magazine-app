import SwiftUI

/// The editorial heading used by the article header and its local UI checks.
struct ArticleHeaderTitle: View {
    let text: String
    let textColor: Color
    @ScaledMetric(relativeTo: .largeTitle) private var fontSize: CGFloat = 34
    #if DEBUG && targetEnvironment(simulator)
    var onTextFrame: ((CGRect) -> Void)? = nil
    #endif

    var body: some View {
        measuredText
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal)
    }

    @ViewBuilder private var measuredText: some View {
        #if DEBUG && targetEnvironment(simulator)
        styledText.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
            onTextFrame?($0)
        }
        #else
        styledText
        #endif
    }

    private var styledText: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .bold))
            .lineSpacing(4)
            .foregroundColor(textColor)
            .multilineTextAlignment(.center)
    }
}

/// The optional editorial subtitle, preserving the header's normal text treatment.
struct ArticleHeaderSubtitle: View {
    let text: String
    let textColor: Color
    @ScaledMetric(relativeTo: .body) private var fontSize: CGFloat = 18
    #if DEBUG && targetEnvironment(simulator)
    var onTextFrame: ((CGRect) -> Void)? = nil
    #endif

    var body: some View {
        measuredText
            .padding(.horizontal)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
    }

    @ViewBuilder private var measuredText: some View {
        #if DEBUG && targetEnvironment(simulator)
        styledText.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
            onTextFrame?($0)
        }
        #else
        styledText
        #endif
    }

    private var styledText: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .medium))
            .foregroundColor(textColor)
    }
}
