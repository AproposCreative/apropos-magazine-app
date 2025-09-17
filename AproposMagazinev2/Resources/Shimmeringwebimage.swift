//
//  Shimmeringwebimage.swift
//  AproposMagazinev2
//
//  Created by AuthentiCode on 01/08/25.
//
import SwiftUI
import SDWebImageSwiftUI
import Shimmer


struct ShimmeringWebImage: View {
    let imageURL: String
    let retryLimit: Int = 3
    @State private var isLoaded = false
    @State private var loadFailed = false
    @State private var retryCount = 0

    var body: some View {
        ZStack {
            // Shimmer + Placeholder
            if !isLoaded {
                Image("loading_placeholder")
                    .resizable()
                    .scaledToFill()
                    .overlay(
                        Color.black.opacity(0.15)
                            .shimmering()
                    )
                    .clipped()
            }

            WebImage(url: URL(string: imageURL), options: [.retryFailed, .refreshCached])
                .resizable()
                .onSuccess { _, _, _ in
                    withAnimation {
                        isLoaded = true
                        loadFailed = false
                    }
                }
                .onFailure { error in
                    print("Image load failed: \(error.localizedDescription)")
                    loadFailed = true
                    isLoaded = false
                    retryLoadIfNeeded()
                }
                .scaledToFill()
                .clipped()
                .opacity(isLoaded ? 1 : 0)
        }
        .frame(height: 200)
        .cornerRadius(12)
        .clipped()
    }

    private func retryLoadIfNeeded() {
        guard retryCount < retryLimit else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            retryCount += 1
            isLoaded = false
            loadFailed = false
        }
    }
}
