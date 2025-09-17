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
                fetchAuthor(by: authorID)
            }
        }
    }

    private func fetchAuthor(by id: String) {
        // Safety check: ensure ID is not empty
        guard !id.isEmpty else {
            print("❌ Author ID is empty")
            return
        }
        
        let urlString = "https://api.webflow.com/v2/collections/67dbf17ba540975b5b21c294/items/\(id)"
        guard let url = URL(string: urlString) else { 
            print("❌ Invalid URL: \(urlString)")
            return 
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("81734a0b8bd3e2352d9325258ad958eea1626c447113661c97d13b5d3b12efa1", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
            }

            // Check for network errors
            if let error = error {
                print("❌ Network error: \(error.localizedDescription)")
                return
            }
            
            // Check for HTTP errors
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                print("❌ HTTP error: \(httpResponse.statusCode)")
                return
            }

            guard let data = data else { 
                print("❌ No data received")
                return 
            }

            do {
                let decoder = JSONDecoder()
                let wrapper = try decoder.decode(AuthorWrapper.self, from: data)
                DispatchQueue.main.async {
                    self.author = wrapper.toAuthor()
                }
            } catch {
                print("❌ JSON Decode error:", error)
                print("Raw response:", String(data: data, encoding: .utf8) ?? "Invalid")
            }
        }.resume()
    }
}
