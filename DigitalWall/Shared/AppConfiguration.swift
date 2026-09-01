import Foundation

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
