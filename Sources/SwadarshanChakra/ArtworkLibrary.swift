import AppKit
import ImageIO
import MeditationCore

@MainActor
final class ArtworkLibrary {
    private let images: [Int: NSImage]
    let brandIcon: NSImage

    static var resourceBundle: Bundle {
        // SwiftPM's fallback path is a build-directory path. A distributable .app must use its
        // own embedded resource bundle, even after it is moved to a different machine.
        if let url = Bundle.main.resourceURL?.appendingPathComponent("SwadarshanChakra_SwadarshanChakra.bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return .module
    }

    init() throws {
        guard let iconURL = Self.resourceBundle.url(forResource: "icon", withExtension: "png", subdirectory: "Branding"),
              let icon = NSImage(contentsOf: iconURL) else {
            throw ArtworkError.missing("icon.png")
        }
        brandIcon = icon
        var decoded: [Int: NSImage] = [:]
        for stage in Stage.all {
            guard let url = Self.resourceBundle.url(forResource: stage.fileName, withExtension: nil, subdirectory: "Artwork"),
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 4096,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else {
                throw ArtworkError.missing(stage.fileName)
            }
            // Decode once, retaining the original aspect ratio. The supplied files stay untouched.
            decoded[stage.id] = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }
        images = decoded
    }

    func image(for stage: Stage) -> NSImage { images[stage.id]! }

    enum ArtworkError: LocalizedError {
        case missing(String)
        var errorDescription: String? {
            switch self {
            case .missing(let file): return "The supplied image \(file) could not be loaded. Rebuild the app with all five original pictures and the supplied icon before starting a practice."
            }
        }
    }
}
