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
        let greenHue = 0.38
        let goldHue = 0.115
        let flameHue = 0.025
        let earnedHours = max(hours, 4)

        if earnedHours <= 10 {
            let progress = Double(earnedHours - 4) / 6
            let hue = greenHue + (goldHue - greenHue) * progress
            let brightness = 0.74 + 0.18 * progress
            return Color(hue: hue, saturation: 0.78, brightness: brightness)
        }

        let extraHours = Double(earnedHours - 10)
        let heatProgress = min(extraHours / 8, 1)
        let hue = goldHue + (flameHue - goldHue) * heatProgress
        let pulse = (sin(extraHours * 0.85) + 1) / 2
        let brightness = 0.84 + pulse * 0.12
        let saturation = 0.78 + heatProgress * 0.16
        return Color(hue: hue, saturation: saturation, brightness: brightness)
    }
}

enum AppConfiguration {
    static let appGroupIdentifier = Bundle.main.object(
        forInfoDictionaryKey: "DigitalWallAppGroupIdentifier"
    ) as? String ?? "group.com.example.DigitalWall"
    static let urlScheme = "digitalwall2"

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
