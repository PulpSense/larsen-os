import Foundation

enum WallPersistence {
    static func load() -> WallState {
        guard let data = try? Data(contentsOf: AppConfiguration.stateFileURL),
              let state = try? JSONDecoder().decode(WallState.self, from: data) else {
            return .empty
        }
        return state
    }

    static func save(_ state: WallState) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: AppConfiguration.stateFileURL, options: .atomic)
    }

    static func exportImage(_ image: VisionImage, to directory: URL) throws -> URL {
        let source = imageURL(for: image)
        let fileManager = FileManager.default
        let baseName = source.deletingPathExtension().lastPathComponent
        let fileExtension = source.pathExtension
        var destination = directory.appendingPathComponent(image.fileName)
        var suffix = 2

        while fileManager.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent("\(baseName) (\(suffix))")
            if !fileExtension.isEmpty {
                destination.appendPathExtension(fileExtension)
            }
            suffix += 1
        }

        try fileManager.copyItem(at: source, to: destination)
        return destination
    }

    static func exportImages(_ images: [VisionImage], boardName: String, to directory: URL) throws -> URL {
        guard !images.isEmpty else {
            throw CocoaError(.fileNoSuchFile)
        }

        let fileManager = FileManager.default
        let invalidCharacters = CharacterSet(charactersIn: "/:\\").union(.controlCharacters)
        let sanitizedName = boardName
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = sanitizedName.isEmpty ? "Vision board" : String(sanitizedName.prefix(50))
        let folderName = "Digital Wall - \(name)"
        var folder = directory.appendingPathComponent(folderName, isDirectory: true)
        var suffix = 2

        while fileManager.fileExists(atPath: folder.path) {
            folder = directory.appendingPathComponent("\(folderName) (\(suffix))", isDirectory: true)
            suffix += 1
        }

        try fileManager.createDirectory(at: folder, withIntermediateDirectories: false)
        do {
            for image in images {
                _ = try exportImage(image, to: folder)
            }
            return folder
        } catch {
            try? fileManager.removeItem(at: folder)
            throw error
        }
    }

    static func imageURL(for image: VisionImage) -> URL {
        AppConfiguration.imagesDirectoryURL.appendingPathComponent(image.fileName)
    }
}
