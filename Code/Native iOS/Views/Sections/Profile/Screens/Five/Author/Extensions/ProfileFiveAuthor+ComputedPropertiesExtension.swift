//
//  ProfileFiveAuthor+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension ProfileFiveAuthorView {
    
    // MARK: - Computed properties:
    
    /// Name of the author to display:
    var name: String {
        author.name
    }
    
    /// Username of the author to display:
    var username: String {
        author.username
    }
    
    /// Title of the 'Subscribe' button:
    var subscribeTitle: String {
        isSubscribed ? "Subscribed" : "Subscribe"
    }
    
    /// Icon of the 'Subscribe' button:
    var subscribeIcon: String {
        isSubscribed ? Icons.checkmarkCircle : Icons.plusCircle
    }
    
    /// Image of the author to display:
    var image: Image {
        .init(author.image)
    }
    
    /// Font of the 'Subscribe' button:
    var subscribeFont: Font {
        .subheadline.bold()
    }
    
    /// Padding around the content of the 'Subscribe' button:
    var subscribePadding: Double {
        8
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the user is subscribed to the author:
    private var isSubscribed: Bool {
        author.isSubscribed
    }
}
