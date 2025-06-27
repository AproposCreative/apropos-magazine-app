//
//  ProfileFiveArticles+ComputedPropertiesExtension.swift
//  Native
//

import Foundation

extension ProfileFiveArticlesView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be shown at all:
    var isShowing: Bool {
        !articles.isEmpty
    }
    
    /// An array of the types of the articles to select from:
    var articleTypes: [NT_ProfileAuthorArticleType] {
        NT_ProfileAuthorArticleType.allCases
    }
    
    /// An array of the articles to display:
    var articles: [NT_BlogArticle] {
        articles(articleType)
    }
    
    /// Spacing between the content of the view:
    var spacing: Double {
        16
    }
    
    /// Size of the frame of each of the icons of the articles that is based on the size of the dynamic type that is currently selected:
    var iconFrame: CGFloat? {
        dynamicTypeSize >= .accessibility1 ? nil : 22
    }
}
