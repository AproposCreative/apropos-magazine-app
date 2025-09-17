import SwiftUI

struct NotificationSettingsView: View {
    @ObservedObject private var userManager = UserManager.shared
    @ObservedObject private var notificationService = NotificationService.shared
    @State private var preferences: NotificationPreferences = NotificationPreferences()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notifikationer")
                .font(.headline)
            
            VStack(spacing: 8) {
                NotificationToggle(
                    title: "Nye artikler",
                    subtitle: "Få besked om nye artikler",
                    isOn: $preferences.newArticles
                )
                
                NotificationToggle(
                    title: "Festival reminders",
                    subtitle: "Påmindelser om kommende festivaler",
                    isOn: $preferences.festivalReminders
                )
                
                NotificationToggle(
                    title: "Breaking news",
                    subtitle: "Vigtige nyheder og opdateringer",
                    isOn: $preferences.breakingNews
                )
                
                NotificationToggle(
                    title: "Ugentlig digest",
                    subtitle: "Ugens bedste artikler hver søndag",
                    isOn: $preferences.weeklyDigest
                )
            }
            
            // Quiet Hours
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Stille timer", isOn: $preferences.quietHours.enabled)
                    .font(.subheadline)
                
                if preferences.quietHours.enabled {
                    HStack {
                        Text("Fra:")
                        DatePicker("", selection: $preferences.quietHours.startTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                        
                        Spacer()
                        
                        Text("Til:")
                        DatePicker("", selection: $preferences.quietHours.endTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            .padding(.top, 8)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            if let user = userManager.currentUser {
                preferences = user.notificationPreferences
            }
        }
        .onChange(of: preferences) { _, _ in
            userManager.updateNotificationPreferences(preferences)
            notificationService.updateNotificationPreferences(preferences)
        }
    }
}

struct NotificationToggle: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
    }
}
