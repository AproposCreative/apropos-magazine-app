import Foundation

enum NotificationDeliveryPolicy {
    private static let deliveryLogKey = "local_notification_delivery_log_v1"
    private static let maxDeliveriesPerDay = 2
    private static let minimumInterval: TimeInterval = 4 * 3600

    static func shouldScheduleLocalNotification(
        at date: Date = Date(),
        settings: NotificationSettings
    ) -> Bool {
        if settings.quietHours.enabled, isWithinQuietHours(date, quietHours: settings.quietHours) {
            return false
        }

        let recent = loadRecentDeliveries(referenceDate: date)
        if recent.count >= maxDeliveriesPerDay {
            return false
        }

        if let last = recent.last, date.timeIntervalSince(last) < minimumInterval {
            return false
        }

        return true
    }

    static func recordLocalNotificationDelivered(at date: Date = Date()) {
        var timestamps = loadRecentDeliveries(referenceDate: date)
        timestamps.append(date)
        timestamps = timestamps.suffix(maxDeliveriesPerDay)
        UserDefaults.standard.set(timestamps.map(\.timeIntervalSince1970), forKey: deliveryLogKey)
    }

    static func isWithinQuietHours(
        _ date: Date,
        quietHours: NotificationSettings.QuietHours
    ) -> Bool {
        guard quietHours.enabled else { return false }

        let calendar = Calendar.current
        let start = calendar.dateComponents([.hour, .minute], from: quietHours.startTime)
        let end = calendar.dateComponents([.hour, .minute], from: quietHours.endTime)
        let current = calendar.dateComponents([.hour, .minute], from: date)

        guard let startMinutes = minutes(from: start),
              let endMinutes = minutes(from: end),
              let currentMinutes = minutes(from: current) else {
            return false
        }

        if startMinutes <= endMinutes {
            return currentMinutes >= startMinutes && currentMinutes < endMinutes
        }

        return currentMinutes >= startMinutes || currentMinutes < endMinutes
    }

    private static func loadRecentDeliveries(referenceDate: Date) -> [Date] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: referenceDate)

        let raw = UserDefaults.standard.array(forKey: deliveryLogKey) as? [TimeInterval] ?? []
        return raw
            .map(Date.init(timeIntervalSince1970:))
            .filter { $0 >= dayStart }
            .sorted()
    }

    private static func minutes(from components: DateComponents) -> Int? {
        guard let hour = components.hour, let minute = components.minute else { return nil }
        return hour * 60 + minute
    }
}
