//
//  ProfileTwoAccount+ComputedPropertiesExtension.swift
//  Native
//

import SwiftUI

extension ProfileTwoAccountView {
    
    // MARK: - Computed properties:
    
    /// 'Bool' value indicating whether or not the content of the view should be moved that is based on the size of the dynamic type that is currently selected:
    var shouldMoveContent: Bool {
        dynamicTypeSize >= .accessibility1
    }
    
    /// An array of the stats to display:
    var stats: [NT_ProfileAccountStat] {
        account.stats
    }
    
    /// An array of the columns to display the stats in the grid:
    var columns: [GridItem] {
        [
            .init(
                .adaptive(
                    minimum: gridItemMinWidth,
                    maximum: gridItemMaxWidth
                ),
                spacing: statsSpacing,
                alignment: .topLeading
            )
        ]
    }
    
    /// Name of the account to display:
    var name: String {
        account.name
    }
    
    /// Username of the account to display:
    var username: String {
        account.username
    }
    
    /// Title of the 'Follow' button:
    var followTitle: String {
        isFollowing ? "Following" : "Follow"
    }
    
    /// Icon of the 'Follow' button:
    var followIcon: String {
        isFollowing ? Icons.checkmarkCircle : Icons.plusCircle
    }
    
    /// Color of the background of the view:
    var backgroundColor: Color {
        .init(.secondarySystemBackground)
    }
    
    /// Image of the account to display:
    var image: Image {
        .init(account.image)
    }
    
    /// Spacing between the stats:
    var statsSpacing: Double {
        16
    }
    
    /// Padding around the content of each of the stats:
    var statPadding: Double {
        12
    }
    
    /// Spacing between the buttons that are displayed on the view:
    var buttonsSpacing: Double {
        8
    }
    
    /// Alignment of each of the titles of the buttons that are displayed on the view:
    var buttonTitleAlignment: TextAlignment {
        .leading
    }
    
    /// Style of the buttons that are displayed on the view:
    var buttonStyle: NT_LabelStyle {
        .titleAndIcon
    }
    
    // MARK: - Private computed properties:
    
    /// 'Bool' value indicating whether or not the user is following the account:
    private var isFollowing: Bool {
        account.isFollowing
    }
    
    /// Minimum width that each of the grid items should have that is based on the size of the dynamic type that is currently selected:
    private var gridItemMinWidth: Double {
        shouldMoveContent ? 200 : 96
    }
    
    /// Maximum width that each of the grid items can have that is based on the size of the dynamic type that is currently selected:
    private var gridItemMaxWidth: Double {
        shouldMoveContent ? 400 : 144
    }
}
