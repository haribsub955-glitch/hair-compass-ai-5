import UIKit

/// Saves JPEGs to the app's Documents directory and returns a relative path.
/// PhotoRecord stores the path, never the image bytes.
final class PhotoStore {
    static let shared = PhotoStore()
    private init() {}

    private var directory: URL {
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

    func load(_ path: String) -> UIImage? {
        guard !path.isEmpty else { return nil }
        let url = directory.appendingPathComponent(path)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    func delete(_ path: String) {
        guard !path.isEmpty else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(path))
    }

    // MARK: - Raw bytes (backup / restore)

    /// The stored JPEG bytes exactly as written — used by backup so no lossy re-encode occurs.
    func loadData(_ path: String) -> Data? {
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
