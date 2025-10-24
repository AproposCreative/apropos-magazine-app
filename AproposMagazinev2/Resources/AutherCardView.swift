//
//  AutherCardView.swift
//  AproposMagazinev2
//
//  Created by AuthentiCode on 01/08/25.
//
import SwiftUI
import SDWebImageSwiftUI

struct AuthorCardView: View {
    let authorID: String

    @State private var isLoading = true
    @State private var author: Author?
    @State private var isFetching = false
    @EnvironmentObject private var viewModel: ArticleViewModel

    private func resolveCachedAuthor() {
        guard author == nil else { return }

        if let cached = viewModel.authors.first(where: { $0.id == authorID }) {
            author = cached
            isLoading = false
        }
    }

    var body: some View {
        HStack(spacing: 5) {
             if let author = author {
                // Safety check for photo URL - photoURL is not optional but can be empty
                if !author.photoURL.isEmpty, let url = URL(string: author.photoURL) {
                    WebImage(url: url)
                        .resizable()
                        .indicator(.activity)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 106, height: 86)
                } else {
                    // Fallback image if no photo URL
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 106, height: 86)
                        .foregroundColor(.gray)
                }
                   
                VStack(alignment: .leading, spacing: 4) {
                    // Safety check for author name - name is not optional but can be empty
                    if !author.name.isEmpty {
                        Text(author.name)
                            .font(.custom("SFProText-Medium", size: 20))
                            .foregroundColor(.primary)
                    }
                    
                    // Safety check for author position - position is not optional but can be empty
                    if !author.position.isEmpty {
                        Text(author.position)
                            .font(.custom("SFProText-Regular", size: 18))
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .lineLimit(2)
                    }
                }
                .padding(.leading ,10)
                Spacer()
            } else if isLoading {
                // Loading state
                HStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(width: 106, height: 86)
                        .padding(.leading , 12)
                        .padding(.trailing , 12)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Loading...")
                            .font(.custom("SFProText-Medium", size: 20))
                            .foregroundColor(.primary)
                    }
                    .padding(.leading ,10)
                    Spacer()
                }
            }
       }
        .onAppear {
            // Safety check: ensure authorID is not empty
            if !authorID.isEmpty {
                resolveCachedAuthor()
                if author == nil {
                    fetchAuthor(by: authorID)
                }
            }
        }
        .onChange(of: viewModel.authors) { _ in
            resolveCachedAuthor()
        }
    }

    private func fetchAuthor(by id: String) {
        // Safety check: ensure ID is not empty
        guard !id.isEmpty else {
            print("❌ Author ID is empty")
            isLoading = false
            return
        }

        guard !isFetching else { return }
        isFetching = true

        viewModel.fetchAuthor(by: id) { result in
            DispatchQueue.main.async {
                isFetching = false
                isLoading = false

                switch result {
                case .success(let fetchedAuthor):
                    author = fetchedAuthor
                case .failure(let error):
                    // Avoid spamming the console with repeated errors for the same author
                    if author == nil {
                        print("❌ Failed to fetch author \(id): \(error.localizedDescription)")
                    }
                }
            }
        }
    }
}
