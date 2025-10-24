import SwiftUI

struct AppSettings: View {
    @AppStorage("selectedTopics") var selectedTopics: String = ""

    var body: some View {
        Form {
            Section(header: Text("Vælg dine emner")) {
                Toggle("Koncerter", isOn: Binding(
                    get: { selectedTopics.contains("Koncerter") },
                    set: { selectedTopics = update(topic: "Koncerter", active: $0) }
                ))
                Toggle("Serier", isOn: Binding(
                    get: { selectedTopics.contains("Serier") },
                    set: { selectedTopics = update(topic: "Serier", active: $0) }
                ))
            }
        }
        .navigationTitle("Indstillinger")
    }

    func update(topic: String, active: Bool) -> String {
        var topics = Set(selectedTopics.components(separatedBy: ",").filter { !$0.isEmpty })
        if active {
            topics.insert(topic)
        } else {
            topics.remove(topic)
        }
        return topics.sorted().joined(separator: ",")
    }
} 
