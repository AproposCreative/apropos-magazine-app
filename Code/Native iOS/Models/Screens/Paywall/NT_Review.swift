//
//  NT_Review.swift
//  Native
//

import Foundation

enum NT_Review: Int {
    
    // MARK: - Cases:
    
    /// You can add more reviews by adding more cases below:
    case first
    case second
    case third
    
    // MARK: - Computed properties:
    
    /// Identifier of the review:
    var id: Int {
        rawValue
    }
    
    /// Title of the review:
    var title: String {
        switch self {
        case .first: return "Truly Amazing"
        case .second: return "I am happy"
        case .third: return "Loving this app!!"
        }
    }
    
    /// Subtitle of the review:
    var subtitle: String {
        switch self {
        case .first: return "I liked this app from the first sight - the UI is so intuitive and it has a ton of great features too."
        case .second: return "I wasn't sure if this app would suit me, but after trying it out for a few days, I can confirm it's awesome!"
        case .third: return "Such a nice banking app that has everything I would ever want plus a lot more for a low fee of $2.99 a month."
        }
    }
    
    /// Image of the person who left the review to display on the eighth paywall screen (Only applicable to some of the screens):
    var paywall8Image: String {
        switch self {
        case .first: return Images.paywall81
        case .second: return Images.paywall82
        case .third: return Images.paywall83
        }
    }
    
    /// Image of the person who left the review to display on the tenth paywall screen (Only applicable to some of the screens):
    var paywall10Image: String {
        switch self {
        case .first: return Images.paywall101
        case .second: return Images.paywall102
        case .third: return Images.paywall103
        }
    }
    
    /// Image of the person who left the review to display on the eleventh paywall screen (Only applicable to some of the screens):
    var paywall11Image: String {
        switch self {
        case .first: return Images.paywall111
        case .second: return Images.paywall112
        case .third: return Images.paywall113
        }
    }
    
    /// Image of the person who left the review to display on the thirteenth paywall screen (Only applicable to some of the screens):
    var paywall13Image: String {
        switch self {
        case .first: return Images.paywall131
        case .second: return Images.paywall132
        case .third: return Images.paywall133
        }
    }
    
    /// Number of the stars that the user has given to the app:
    var rating: Int {
        switch self {
        case .first: return 5
        case .second: return 5
        case .third: return 5
        }
    }
}

// MARK: - Identifiable:

extension NT_Review: Identifiable {  }

// MARK: - CaseIterable:

extension NT_Review: CaseIterable {  }

// MARK: - Equatable:

extension NT_Review: Equatable {  }

// MARK: - Hashable:

extension NT_Review: Hashable {  }
