import AppKit
import SwiftUI

/// Loads remote artwork with an in-memory cache plus a 300 MB disk cache, so scrolling the grid doesn't re-download.
@MainActor
final class ImageLoader {
    static let shared = ImageLoader()

    private let memory = NSCache<NSURL, NSImage>()
    private let session: URLSession
    private var failed = Set<URL>()

    private init() {
        let cacheFolder = URL.cachesDirectory.appending(path: "MacGamingLauncher/Artwork")
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 32 << 20, diskCapacity: 300 << 20, directory: cacheFolder)
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: configuration)
        memory.countLimit = 400
        memory.totalCostLimit = 1 << 30 // ~1 GB of decoded pixels (hero art is ~19 MB each)
    }

    func cached(_ url: URL) -> NSImage? { memory.object(forKey: url as NSURL) }

    /// Returns the first URL that loads, or `nil`.
    func image(for urls: [URL]) async -> NSImage? {
        for url in urls where !failed.contains(url) {
            if let image = cached(url) { return image }
            do {
                let (data, response) = try await session.data(from: url)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard status == 200, let image = NSImage(data: data) else {
                    // Only permanent misses are remembered; 5xx/429 may succeed later.
                    if status == 403 || status == 404 || status == 200 { failed.insert(url) }
                    continue
                }
                let pixels = image.representations.map { $0.pixelsWide * $0.pixelsHigh }.max() ?? 0
                memory.setObject(image, forKey: url as NSURL, cost: pixels * 4)
                return image
            } catch is CancellationError {
                return nil
            } catch let error as URLError where error.code == .cancelled {
                return nil
            } catch {
                continue
            }
        }
        return nil
    }
}

struct CachedImage<Placeholder: View>: View {
    let urls: [URL]
    @ViewBuilder let placeholder: () -> Placeholder
    @State private var image: NSImage?

    init(_ urls: [URL?], @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.urls = urls.compactMap { $0 }
        self.placeholder = placeholder
        _image = State(initialValue: self.urls.lazy.compactMap { ImageLoader.shared.cached($0) }.first)
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable()
            } else {
                placeholder()
            }
        }
        .task(id: urls) {
            if let cached = urls.lazy.compactMap({ ImageLoader.shared.cached($0) }).first {
                image = cached
            } else if let loaded = await ImageLoader.shared.image(for: urls) {
                image = loaded
            }
        }
    }
}
