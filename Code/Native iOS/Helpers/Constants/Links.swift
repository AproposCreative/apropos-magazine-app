//
//  Links.swift
//  Native
//

import Foundation

struct Links {
    
    // MARK: - Properties:
    
    /// Link to the page with the terms of service of the app (You can replace it with your own link, It's okay to force unwrap here given that this is a static URL and should technically always be there):
    static let termsOfService: URL = URL(string: "https://applayouts.com/terms-of-use")!
    
    /// Link to the page with the privacy policy of the app (You can replace it with your own link, It's okay to force unwrap here given that this is a static URL and should technically always be there):
    static let privacyPolicy: URL = URL(string: "https://applayouts.com/privacy-policy")!
}
