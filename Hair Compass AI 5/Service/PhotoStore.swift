import ImageIO
import UIKit

/// Saves JPEGs to the app's Documents directory and returns a relative path.
/// PhotoRecord stores the path, never the image bytes.
final class PhotoStore {
    // `nonisolated` (this module defaults unannotated declarations to the main actor): the
    // singleton itself, its directory lookup and the raw-bytes/thumbnail readers below are
    // plain file I/O with no actor-isolated state, and background exporters (backup, the visit
    // PDF) need to call them from a detached task without hopping back to the main actor.
    nonisolated static let shared = PhotoStore()
    private init() {}

    // `nonisolated(unsafe)`, not just `nonisolated`: `NSCache` isn't `Sendable`-annotated in the
    // SDK even though it's documented thread-safe, so this opts out of that check rather than
    // the actor-isolation one (already handled by `nonisolated` on the methods that use it).
    nonisolated(unsafe) private let cache = NSCache<NSString, UIImage>()

    nonisolated private var directory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ScalpPhotos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Returns the stored file name (relative path) on success.
    func save(_ image: UIImage, quality: CGFloat = 0.82) -> String? {
        guard let data = image.jpegData(compressionQuality: quality) else { return nil }
        let name = "\(UUID().uuidString).jpg"
        let url = directory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    nonisolated func load(_ path: String) -> UIImage? {
        guard !path.isEmpty else { return nil }
        let url = directory.appendingPathComponent(path)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Loads a downsampled thumbnail for list/grid display without decoding the full source image.
    nonisolated func loadThumbnail(_ path: String, maxPixel: CGFloat = 640) -> UIImage? {
        guard !path.isEmpty else { return nil }
        let key = "\(path)-\(Int(maxPixel))" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let url = directory.appendingPathComponent(path)
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
            return load(path)
        }

        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel)
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
            return load(path)
        }

        let image = UIImage(cgImage: cgImage)
        cache.setObject(image, forKey: key)
        return image
    }

    func delete(_ path: String) {
        guard !path.isEmpty else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(path))
    }

    // MARK: - Raw bytes (backup / restore)

    /// The stored JPEG bytes exactly as written — used by backup so no lossy re-encode occurs.
    nonisolated func loadData(_ path: String) -> Data? {
        guard !path.isEmpty else { return nil }
        return try? Data(contentsOf: directory.appendingPathComponent(path))
    }

    /// Writes raw image bytes from a restore as a new stored file. Returns the relative path.
    func saveData(_ data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        let name = "\(UUID().uuidString).jpg"
        do {
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }
}
