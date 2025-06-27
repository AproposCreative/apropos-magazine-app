//
//  PaywallFifteenView.swift
//  Native
//

import SwiftUI

struct PaywallFifteenView: View {
    
    // MARK: - Properties:
    
    /// An actual pro plan that the users can purchase:
    @State var plan: NT_ProPlan? = nil
    
    /// 'Bool' value indicating whether or not the data is currently being fetched:
    @State var isFetching: Bool = true
    
    // MARK: - Private properties:
    
    /// Dismisses the view:
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - View:
    
    var body: some View {
        content
    }
    
    private var content: some View {
        item
            .background(imageContent)
            .localizedNavigationTitle(
                title: "AppLayouts Pro",
                isLocalized: false
            )
            .toolbarButton(
                title: "Done",
                color: .primary,
                action: dismiss.callAsFunction
            )
            .animation(
                .default,
                value: plan
            )
            .animation(
                .default,
                value: isFetching
            )
            .task {
                await fetchPlan()
            }
            .navigationStack()
            .environment(
                \.colorScheme,
                 .dark
            )
    }
}

// MARK: - Item:

private extension PaywallFifteenView {
    private var item: some View {
        VStack(
            alignment: .leading,
            spacing: 0
        ) {
            itemContent
        }
    }
    
    @ViewBuilder
    private var itemContent: some View {
        scroll
        toolbar
    }
}

// MARK: - Image:

private extension PaywallFifteenView {
    private var imageContent: some View {
        ZStack {
            imageItem
        }
    }
    
    @ViewBuilder
    private var imageItem: some View {
        imageItemContent
        imageOverlay
    }
    
    private var imageItemContent: some View {
        image
            .resizable()
            .ignoresSafeArea()
    }
    
    private var imageOverlay: some View {
        imageOverlayColor
            .ignoresSafeArea()
    }
}

// MARK: - Scroll:

private extension PaywallFifteenView {
    private var scroll: some View {
        scrollContent
            .safeAreaPadding(
                .all,
                16
            )
            .safeAreaPadding(
                .bottom,
                16
            )
    }
    
    private var scrollContent: some View {
        ScrollView {
            scrollItem
        }
    }
    
    private var scrollItem: some View {
        ZStack {
            scrollItemContent
        }
    }
    
    @ViewBuilder
    private var scrollItemContent: some View {
        scrollItemSpacer
        iconTitleSubtitle
    }
    
    private var scrollItemSpacer: some View {
        Spacer()
            .containerRelativeFrame(
                .vertical,
                alignment: .center
            )
    }
}

// MARK: - Icon, title and subtitle:

private extension PaywallFifteenView {
    private var iconTitleSubtitle: some View {
        iconTitleSubtitleContent
            .accessibilityElement(children: .combine)
    }
    
    private var iconTitleSubtitleContent: some View {
        VStack(
            alignment: .center,
            spacing: 32
        ) {
            iconTitleSubtitleItem
        }
    }
    
    @ViewBuilder
    private var iconTitleSubtitleItem: some View {
        icon
        titleSubtitle
    }
    
    private var icon: some View {
        IconBackgroundView(
            icon: Icons.chevronLeftForwardslashChevronRight,
            size: .ninetySixPixels
        )
    }
    
    private var titleSubtitle: some View {
        VStack(
            alignment: .center,
            spacing: 16
        ) {
            titleSubtitleContent
        }
    }
    
    @ViewBuilder
    private var titleSubtitleContent: some View {
        title
        subtitle
    }
    
    private var title: some View {
        titleContent
            .font(.largeTitle.bold())
            .multilineTextAlignment(.center)
            .foregroundStyle(.primary)
            .dynamicTextHeight()
    }
    
    private var titleContent: some View {
        Text("Supercharge Your \(Text("iOS App Project").foregroundStyle(titleGradient)) 🚀")
    }
    
    private var subtitle: some View {
        subtitleContent
            .font(.title3)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
    }
    
    private var subtitleContent: some View {
        Text("Library of free and premium resources to help you launch your next app quicker.")
    }
}

// MARK: - Toolbar:

private extension PaywallFifteenView {
    private var toolbar: some View {
        BottomToolbarView() {
            toolbarContent
        }
    }
    
    @ViewBuilder
    private var toolbarContent: some View {
        notice
        purchaseLegalButtons
    }
    
    private var notice: some View {
        noticeContent
            .font(.footnote)
            .multilineTextAlignment(.leading)
            .foregroundStyle(.secondary)
    }
    
    private var noticeContent: some View {
        Text("Plan will automatically renew unless cancelled at least 24 hours before the renewal date.")
    }
    
    private var purchaseLegalButtons: some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            purchaseLegalButtonsContent
        }
    }
    
    @ViewBuilder
    private var purchaseLegalButtonsContent: some View {
        purchaseButton
        PaywallTwelveLegalView(isFetching: isFetching)
    }
    
    private var purchaseButton: some View {
        ButtonView(
            title: purchaseTitle,
            isLoading: isFetching,
            isDisabled: !isPlanAvailable,
            action: purchase
        )
    }
}

// MARK: - Preview:

#Preview {
    PaywallFifteenView()
}
