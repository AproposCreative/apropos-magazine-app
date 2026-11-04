import Foundation

/// Resolves onboarding choices without requesting permissions or contacting FCM.
enum NotificationOnboardingPolicy {
    struct Choices {
        let preferences: NotificationPreferences
        let selectedCategoryIds: [String]
    }

    static func choices(allowNotifications: Bool, selectedCategoryIds: [String]) -> Choices {
        // Topic selections also enable article push, so declining must clear
        // them as well as the preference flags before any subscription sync.
        let categoryIds = allowNotifications ? selectedCategoryIds : []
        return Choices(
            preferences: NotificationPreferences(
                newArticles: allowNotifications && categoryIds.isEmpty,
                newPodcasts: allowNotifications,
                festivalReminders: allowNotifications,
                breakingNews: allowNotifications
            ),
            selectedCategoryIds: categoryIds
        )
    }
}
