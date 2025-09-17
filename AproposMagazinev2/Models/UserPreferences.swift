import Foundation
import SwiftUI

// MARK: - Enhanced Reading Preferences

extension ReadingPreferences {
    var lineSpacing: LineSpacing {
        get { LineSpacing(rawValue: UserDefaults.standard.string(forKey: "lineSpacing") ?? "comfortable") ?? .comfortable }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "lineSpacing") }
    }
    
    var paragraphSpacing: CGFloat {
        get { UserDefaults.standard.double(forKey: "paragraphSpacing") }
        set { UserDefaults.standard.set(newValue, forKey: "paragraphSpacing") }
    }
    
    var readingMode: ReadingMode {
        get { ReadingMode(rawValue: UserDefaults.standard.string(forKey: "readingMode") ?? "default") ?? .default }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "readingMode") }
    }
    
    var autoScroll: Bool {
        get { UserDefaults.standard.bool(forKey: "autoScroll") }
        set { UserDefaults.standard.set(newValue, forKey: "autoScroll") }
    }
    
    var showProgress: Bool {
        get { UserDefaults.standard.bool(forKey: "showProgress") }
        set { UserDefaults.standard.set(newValue, forKey: "showProgress") }
    }
}

enum LineSpacing: String, CaseIterable, Codable {
    case tight = "tight"
    case normal = "normal"
    case comfortable = "comfortable"
    case relaxed = "relaxed"
    
    var displayName: String {
        switch self {
        case .tight: return "Tæt"
        case .normal: return "Normal"
        case .comfortable: return "Komfortabel"
        case .relaxed: return "Afslappet"
        }
    }
    
    var value: CGFloat {
        switch self {
        case .tight: return 1.0
        case .normal: return 1.2
        case .comfortable: return 1.4
        case .relaxed: return 1.6
        }
    }
}

enum ReadingMode: String, CaseIterable, Codable {
    case `default` = "default"
    case focus = "focus"
    case distractionFree = "distractionFree"
    case night = "night"
    
    var displayName: String {
        switch self {
        case .default: return "Standard"
        case .focus: return "Fokus"
        case .distractionFree: return "Uforstyrret"
        case .night: return "Nattilstand"
        }
    }
    
    var backgroundColor: Color {
        switch self {
        case .default: return Color(.systemBackground)
        case .focus: return Color(.systemGray6)
        case .distractionFree: return Color(.systemBackground)
        case .night: return Color.black
        }
    }
    
    var textColor: Color {
        switch self {
        case .default: return Color(.label)
        case .focus: return Color(.label)
        case .distractionFree: return Color(.label)
        case .night: return Color.white
        }
    }
}

// MARK: - Appearance Preferences

struct AppearancePreferences: Codable, Equatable {
    var accentColor: AccentColor
    var useSystemTheme: Bool
    var showAnimations: Bool
    var reduceMotion: Bool
    
    init() {
        self.accentColor = .blue
        self.useSystemTheme = true
        self.showAnimations = true
        self.reduceMotion = false
    }
}

enum AccentColor: String, CaseIterable, Codable {
    case blue = "blue"
    case purple = "purple"
    case green = "green"
    case orange = "orange"
    case red = "red"
    case pink = "pink"
    case yellow = "yellow"
    case indigo = "indigo"
    
    var displayName: String {
        switch self {
        case .blue: return "Blå"
        case .purple: return "Lilla"
        case .green: return "Grøn"
        case .orange: return "Orange"
        case .red: return "Rød"
        case .pink: return "Pink"
        case .yellow: return "Gul"
        case .indigo: return "Indigo"
        }
    }
    
    var color: Color {
        switch self {
        case .blue: return .blue
        case .purple: return .purple
        case .green: return .green
        case .orange: return .orange
        case .red: return .red
        case .pink: return .pink
        case .yellow: return .yellow
        case .indigo: return .indigo
        }
    }
}

// MARK: - Content Preferences

struct ContentPreferences: Codable, Equatable {
    var showAds: Bool
    var contentFilter: ContentFilter
    var language: Language
    var region: String
    
    init() {
        self.showAds = false
        self.contentFilter = .all
        self.language = .danish
        self.region = "DK"
    }
}

enum ContentFilter: String, CaseIterable, Codable {
    case all = "all"
    case family = "family"
    case mature = "mature"
    
    var displayName: String {
        switch self {
        case .all: return "Alle"
        case .family: return "Familievenlig"
        case .mature: return "Voksen"
        }
    }
}

enum Language: String, CaseIterable, Codable {
    case danish = "da"
    case english = "en"
    case swedish = "sv"
    case norwegian = "no"
    
    var displayName: String {
        switch self {
        case .danish: return "Dansk"
        case .english: return "English"
        case .swedish: return "Svenska"
        case .norwegian: return "Norsk"
        }
    }
}

// MARK: - Accessibility Preferences

struct AccessibilityPreferences: Codable, Equatable {
    var boldText: Bool
    var largerText: Bool
    var increaseContrast: Bool
    var reduceTransparency: Bool
    var onOffLabels: Bool
    var voiceOverEnabled: Bool
    
    init() {
        self.boldText = false
        self.largerText = false
        self.increaseContrast = false
        self.reduceTransparency = false
        self.onOffLabels = false
        self.voiceOverEnabled = false
    }
}

// MARK: - Privacy Preferences

struct PrivacyPreferences: Codable, Equatable {
    var analyticsEnabled: Bool
    var crashReportsEnabled: Bool
    var personalizedAds: Bool
    var shareUsageData: Bool
    var locationServices: Bool
    
    init() {
        self.analyticsEnabled = true
        self.crashReportsEnabled = true
        self.personalizedAds = false
        self.shareUsageData = false
        self.locationServices = false
    }
}

// MARK: - Enhanced User Preferences

struct EnhancedUserPreferences: Codable, Equatable {
    var readingPreferences: ReadingPreferences
    var appearancePreferences: AppearancePreferences
    var contentPreferences: ContentPreferences
    var accessibilityPreferences: AccessibilityPreferences
    var privacyPreferences: PrivacyPreferences
    
    init() {
        self.readingPreferences = ReadingPreferences()
        self.appearancePreferences = AppearancePreferences()
        self.contentPreferences = ContentPreferences()
        self.accessibilityPreferences = AccessibilityPreferences()
        self.privacyPreferences = PrivacyPreferences()
    }
}

// MARK: - Preferences Manager

@MainActor
class PreferencesManager: ObservableObject {
    @Published var preferences: EnhancedUserPreferences
    static let shared = PreferencesManager()
    
    private let userDefaults = UserDefaults.standard
    private let preferencesKey = "enhanced_user_preferences"
    
    private init() {
        self.preferences = EnhancedUserPreferences()
        self.preferences = loadPreferences()
    }
    
    // MARK: - Persistence
    
    private func loadPreferences() -> EnhancedUserPreferences {
        guard let data = userDefaults.data(forKey: preferencesKey),
              let preferences = try? JSONDecoder().decode(EnhancedUserPreferences.self, from: data) else {
            return EnhancedUserPreferences()
        }
        return preferences
    }
    
    func savePreferences() {
        if let data = try? JSONEncoder().encode(preferences) {
            userDefaults.set(data, forKey: preferencesKey)
        }
    }
    
    // MARK: - Reading Preferences
    
    func updateFontSize(_ fontSize: FontSize) {
        preferences.readingPreferences.fontSize = fontSize
        savePreferences()
        HapticManager.shared.selection()
    }
    
    func updateLineSpacing(_ lineSpacing: LineSpacing) {
        preferences.readingPreferences.lineSpacing = lineSpacing
        savePreferences()
        HapticManager.shared.selection()
    }
    
    func updateReadingMode(_ mode: ReadingMode) {
        preferences.readingPreferences.readingMode = mode
        savePreferences()
        HapticManager.shared.mediumImpact()
    }
    
    // MARK: - Appearance Preferences
    
    func updateAccentColor(_ color: AccentColor) {
        preferences.appearancePreferences.accentColor = color
        savePreferences()
        HapticManager.shared.selection()
    }
    
    func toggleAnimations() {
        preferences.appearancePreferences.showAnimations.toggle()
        savePreferences()
        HapticManager.shared.lightImpact()
    }
    
    // MARK: - Content Preferences
    
    func toggleShowImages() {
        preferences.contentPreferences.showAds.toggle()
        savePreferences()
        HapticManager.shared.lightImpact()
    }
    
    func updateContentFilter(_ filter: ContentFilter) {
        preferences.contentPreferences.contentFilter = filter
        savePreferences()
        HapticManager.shared.selection()
    }
    
    // MARK: - Accessibility Preferences
    
    func toggleBoldText() {
        preferences.accessibilityPreferences.boldText.toggle()
        savePreferences()
        HapticManager.shared.lightImpact()
    }
    
    func toggleLargerText() {
        preferences.accessibilityPreferences.largerText.toggle()
        savePreferences()
        HapticManager.shared.lightImpact()
    }
    
    // MARK: - Privacy Preferences
    
    func toggleAnalytics() {
        preferences.privacyPreferences.analyticsEnabled.toggle()
        savePreferences()
        HapticManager.shared.lightImpact()
    }
    
    func togglePersonalizedAds() {
        preferences.privacyPreferences.personalizedAds.toggle()
        savePreferences()
        HapticManager.shared.lightImpact()
    }
    
    // MARK: - Reset Preferences
    
    func resetToDefaults() {
        preferences = EnhancedUserPreferences()
        savePreferences()
        HapticManager.shared.heavyImpact()
    }
}

// MARK: - SwiftUI Extensions

extension View {
    func withPreferences() -> some View {
        self.environmentObject(PreferencesManager.shared)
    }
    
    func readingStyle(_ preferences: ReadingPreferences) -> some View {
        self.font(.system(size: preferences.fontSize.size))
            .lineSpacing(preferences.lineSpacing.value)
            .background(preferences.readingMode.backgroundColor)
            .foregroundColor(preferences.readingMode.textColor)
    }
}
