import SwiftUI

// MARK: - App Constants

struct AppConstants {
    
    // MARK: - Spacing
    
    struct Spacing {
        static let small: CGFloat = 8
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let extraLarge: CGFloat = 32
    }
    
    // MARK: - Corner Radius
    
    struct CornerRadius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let extraLarge: CGFloat = 20
    }
    
    // MARK: - Animation
    
    struct Animation {
        static let quick: Double = 0.2
        static let standard: Double = 0.3
        static let slow: Double = 0.5
    }
    
    // MARK: - Image Sizes
    
    struct ImageSize {
        static let thumbnail: CGFloat = 200
        static let avatar: CGFloat = 40
        static let icon: CGFloat = 24
    }
    
    // MARK: - Text Limits
    
    struct TextLimits {
        static let titleLines = 2
        static let descriptionLines = 3
        static let subtitleLines = 1
    }
    
    // MARK: - API
    
    struct API {
        static let baseURL = "https://api.webflow.com/v2/webhooks/f24bc5cc755d7cdd083b8323fc6f2c42b981b71ed48ce4dcbf1fd3eb3f438257"
        static let timeout: TimeInterval = 30
    }
    
    // MARK: - Cache
    
    struct Cache {
        static let maxAge: TimeInterval = 3600 // 1 hour
        static let maxSize: Int = 100 // MB
    }
}

// MARK: - Icon Names

struct Icons {
    static let heart = "heart"
    static let heartFill = "heart.fill"
    static let magnifyingglass = "magnifyingglass"
    static let xmark = "xmark"
    static let arrowRight = "arrow.right"
    static let star = "star"
    static let starFill = "star.fill"
    static let person = "person"
    static let personFill = "person.fill"
    static let house = "house"
    static let houseFill = "house.fill"
    static let docText = "doc.text"
    static let docTextFill = "doc.text.fill"
    static let squareGrid = "square.grid.2x2"
    static let squareGridFill = "square.grid.2x2.fill"
    static let exclamationmarkTriangle = "exclamationmark.triangle.fill"
    static let photo = "photo"
    static let play = "play.fill"
    static let plus = "plus"
    static let minus = "minus"
    static let chevronRight = "chevron.right"
    static let chevronLeft = "chevron.left"
    static let share = "square.and.arrow.up"
    static let bookmark = "bookmark"
    static let bookmarkFill = "bookmark.fill"
    static let clock = "clock"
    static let calendar = "calendar"
    static let tag = "tag"
    static let tagFill = "tag.fill"
    static let gear = "gearshape"
    static let gearFill = "gearshape.fill"
    static let info = "info.circle"
    static let infoFill = "info.circle.fill"
    static let questionmark = "questionmark.circle"
    static let questionmarkFill = "questionmark.circle.fill"
    static let checkmark = "checkmark"
    static let checkmarkCircle = "checkmark.circle"
    static let checkmarkCircleFill = "checkmark.circle.fill"
    static let xmarkCircle = "xmark.circle"
    static let xmarkCircleFill = "xmark.circle.fill"
    static let tray = "tray"
    static let trayFill = "tray.fill"
    static let trash = "trash"
    static let trashFill = "trash.fill"
    static let pencil = "pencil"
    static let pencilFill = "pencil.fill"
    static let camera = "camera"
    static let cameraFill = "camera.fill"
    static let mic = "mic"
    static let micFill = "mic.fill"
    static let location = "location"
    static let locationFill = "location.fill"
    static let phone = "phone"
    static let phoneFill = "phone.fill"
    static let envelope = "envelope"
    static let envelopeFill = "envelope.fill"
    static let link = "link"
    static let wifi = "wifi"
    static let wifiSlash = "wifi.slash"
    static let battery = "battery.100"
    static let battery25 = "battery.25"
    static let battery50 = "battery.50"
    static let battery75 = "battery.75"
    static let battery0 = "battery.0"
    static let batterySlash = "battery.slash"
    static let signal = "antenna.radiowaves.left.and.right"
    static let signalSlash = "antenna.radiowaves.left.and.right.slash"
    static let moon = "moon"
    static let moonFill = "moon.fill"
    static let sun = "sun.max"
    static let sunFill = "sun.max.fill"
    static let cloud = "cloud"
    static let cloudFill = "cloud.fill"
    static let cloudRain = "cloud.rain"
    static let cloudRainFill = "cloud.rain.fill"
    static let cloudSnow = "cloud.snow"
    static let cloudSnowFill = "cloud.snow.fill"
    static let cloudBolt = "cloud.bolt"
    static let cloudBoltFill = "cloud.bolt.fill"
    static let cloudSun = "cloud.sun"
    static let cloudSunFill = "cloud.sun.fill"
    static let cloudMoon = "cloud.moon"
    static let cloudMoonFill = "cloud.moon.fill"
    static let wind = "wind"
    static let snowflake = "snowflake"
    static let thermometer = "thermometer"
    static let thermometerSun = "thermometer.sun"
    static let thermometerSnowflake = "thermometer.snowflake"
    static let drop = "drop"
    static let dropFill = "drop.fill"
    static let flame = "flame"
    static let flameFill = "flame.fill"
    static let bolt = "bolt"
    static let boltFill = "bolt.fill"
    static let boltSlash = "bolt.slash"
    static let boltSlashFill = "bolt.slash.fill"
    static let boltCircle = "bolt.circle"
    static let boltCircleFill = "bolt.circle.fill"
    static let boltSquare = "bolt.square"
    static let boltSquareFill = "bolt.square.fill"
    static let boltHorizontal = "bolt.horizontal"
    static let boltHorizontalFill = "bolt.horizontal.fill"
    static let boltHorizontalCircle = "bolt.horizontal.circle"
    static let boltHorizontalCircleFill = "bolt.horizontal.circle.fill"
    static let boltHorizontalSquare = "bolt.horizontal.square"
    static let boltHorizontalSquareFill = "bolt.horizontal.square.fill"
    static let boltVertical = "bolt.vertical"
    static let boltVerticalFill = "bolt.vertical.fill"
    static let boltVerticalCircle = "bolt.vertical.circle"
    static let boltVerticalCircleFill = "bolt.vertical.circle.fill"
    static let boltVerticalSquare = "bolt.vertical.square"
    static let boltVerticalSquareFill = "bolt.vertical.square.fill"
    static let boltSlashCircle = "bolt.slash.circle"
    static let boltSlashCircleFill = "bolt.slash.circle.fill"
    static let boltSlashSquare = "bolt.slash.square"
    static let boltSlashSquareFill = "bolt.slash.square.fill"
    static let boltSlashHorizontal = "bolt.slash.horizontal"
    static let boltSlashHorizontalFill = "bolt.slash.horizontal.fill"
    static let boltSlashHorizontalCircle = "bolt.slash.horizontal.circle"
    static let boltSlashHorizontalCircleFill = "bolt.slash.horizontal.circle.fill"
    static let boltSlashHorizontalSquare = "bolt.slash.horizontal.square"
    static let boltSlashHorizontalSquareFill = "bolt.slash.horizontal.square.fill"
    static let boltSlashVertical = "bolt.slash.vertical"
    static let boltSlashVerticalFill = "bolt.slash.vertical.fill"
    static let boltSlashVerticalCircle = "bolt.slash.vertical.circle"
    static let boltSlashVerticalCircleFill = "bolt.slash.vertical.circle.fill"
    static let boltSlashVerticalSquare = "bolt.slash.vertical.square"
    static let boltSlashVerticalSquareFill = "bolt.slash.vertical.square.fill"
} 