import Foundation
import SwiftUI

extension Color {
    static let digitalWallFlame = Color(red: 0.98, green: 0.20, blue: 0.055)
}

enum DeepWorkVisuals {
    static func color(for hours: Int) -> Color {
        switch hours {
        case 1: .indigo.opacity(0.30)
        case 2: .indigo.opacity(0.50)
        case 3: .indigo.opacity(0.72)
        case 4...: earnedColor(for: hours)
        default: .secondary.opacity(0.18)
        }
    }

    static func earnedColor(for hours: Int) -> Color {
        let cappedHours = min(max(hours, 4), 10)
        let progress = Double(cappedHours - 4) / 6
        let greenHue = 0.38
        let goldHue = 0.115
        let hue = greenHue + (goldHue - greenHue) * progress
        let brightness = 0.74 + 0.18 * progress
        return Color(hue: hue, saturation: 0.78, brightness: brightness)
    }
}

enum AppConfiguration {
    static let bundleIdentifier = "com.santileoni.DigitalWall"
    static let widgetBundleIdentifier = "com.santileoni.DigitalWall.Widget"
    static let appGroupIdentifier = "group.com.santileoni.DigitalWall"
    static let urlScheme = "digitalwall2"
    static let visionBoardWidgetKind = "DigitalWallVisionBoardWidgetV5"
    static let consistencyWidgetKind = "DigitalWallConsistencyWidgetV3"
    static let phrasesWidgetKind = "DigitalWallEditablePhraseWidgetV3"

    static var sharedContainerURL: URL {
        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) {
            return groupURL
        }

        let fallback = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("DigitalWall", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: fallback,
            withIntermediateDirectories: true
        )
        return fallback
    }

    static var stateFileURL: URL {
        // v2 bypasses a corrupted/blocked early-development state file while
        // leaving that original file untouched for possible recovery.
        sharedContainerURL.appendingPathComponent("wall-state-v2.json")
    }

    static var imagesDirectoryURL: URL {
        sharedContainerURL.appendingPathComponent("VisionImages", isDirectory: true)
    }

}
