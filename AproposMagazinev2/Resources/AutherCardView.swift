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
    @Environment(\.navigationCoordinator) private var navigationCoordinator

    private func resolveCachedAuthor() {
        guard author == nil else { return }

        if let cached = viewModel.authors.first(where: { $0.id == authorID }) {
            author = cached
            isLoading = false
        }
    }

    var body: some View {
        Group {
            if let author {
                Button {
                    navigationCoordinator.navigateToAuthor(author)
                } label: {
                    authorRow(for: author)
                }
                .buttonStyle(.plain)
            } else if isLoading {
                HStack(alignment: .center, spacing: 16) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 82, height: 82)
                        .overlay(
                            ProgressView()
                                .progressViewStyle(.circular)
                        )
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Henter forfatter…")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 12)
        .onAppear {
            if !authorID.isEmpty {
                resolveCachedAuthor()
                if author == nil {
                    fetchAuthor(by: authorID)
                }
            }
        }
        .onChange(of: viewModel.authors) { _, _ in
            resolveCachedAuthor()
        }
    }

    private func authorRow(for author: Author) -> some View {
        HStack(alignment: .center, spacing: 16) {
            authorImage(for: author)
            
            VStack(alignment: .leading, spacing: 6) {
                if !author.name.isEmpty {
                    Text(author.name)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.primary)
                }
                
                if !author.position.isEmpty {
                    Text(author.position)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func authorImage(for author: Author) -> some View {
        if !author.photoURL.isEmpty, let url = URL(string: author.photoURL) {
            WebImage(url: url)
                .resizable()
                .indicator(.activity)
                .aspectRatio(contentMode: .fill)
                .frame(width: 82, height: 82)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 82, height: 82)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundColor(.gray)
                )
        }
    }

    private func fetchAuthor(by id: String) {
        guard !id.isEmpty else {
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
                case .failure:
                    break
                }
            }
        }
    }
}
