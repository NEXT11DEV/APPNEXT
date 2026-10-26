import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers

@MainActor
private final class AppIconMemoryCache {
    static let shared = AppIconMemoryCache()

    private let cache = NSCache<NSURL, UIImage>()

    private init() {
        // Icons are decorative list content. Keep a firm memory ceiling so a
        // large source catalog cannot gradually pressure the app into a crash.
        cache.countLimit = 160
        cache.totalCostLimit = 20 * 1_024 * 1_024
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func insert(_ image: UIImage, for url: URL) {
        let width = image.cgImage?.width ?? Int(image.size.width)
        let height = image.cgImage?.height ?? Int(image.size.height)
        let byteCost = max(width * height * 4, 1)
        cache.setObject(image, forKey: url as NSURL, cost: byteCost)
    }
}

private actor AppIconDataLoader {
    static let shared = AppIconDataLoader()

    private var inFlight: [URL: Task<Data?, Never>] = [:]
    private let maximumResponseBytes = 6 * 1_024 * 1_024

    func data(for url: URL) async -> Data? {
        if let existing = inFlight[url] {
            return await existing.value
        }

        let responseByteLimit = maximumResponseBytes
        let task: Task<Data?, Never> = Task.detached(priority: .utility) { () -> Data? in
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            request.timeoutInterval = 12
            request.httpShouldHandleCookies = false

            guard let (bytes, response) = try? await URLSession.shared.bytes(for: request),
                  let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  httpResponse.expectedContentLength <= Int64(responseByteLimit) || httpResponse.expectedContentLength == -1 else {
                return nil
            }

            var data = Data()
            data.reserveCapacity(Int(min(max(httpResponse.expectedContentLength, 0), Int64(responseByteLimit))))

            do {
                for try await byte in bytes {
                    guard data.count < responseByteLimit else { return nil }
                    data.append(byte)
                }
            } catch {
                return nil
            }

            return data.isEmpty ? nil : data
        }

        inFlight[url] = task
        let result = await task.value
        inFlight[url] = nil
        return result
    }
}

private enum AppIconThumbnail {
    static func data(from sourceData: Data, maximumPixelSize: Int) -> Data? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(sourceData as CFData, sourceOptions) else {
            return nil
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return nil
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(destination, thumbnail, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}

struct CachedAppIcon: View {
    let url: URL?
    let size: CGFloat
    let cornerRadius: CGFloat

    @Environment(\.forgeTheme) private var T
    @State private var image: UIImage?

    init(url: URL?, size: CGFloat = 44, cornerRadius: CGFloat = 11) {
        self.url = url
        self.size = size
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: size * 0.34, weight: .medium))
                    .foregroundColor(Color(red: 0.08, green: 0.49, blue: 0.92).opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: size, height: size)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.6)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        guard let url else {
            image = nil
            return
        }

        if url.isFileURL, let local = UIImage(contentsOfFile: url.path) {
            image = local
            return
        }
        if let cached = AppIconMemoryCache.shared.image(for: url) {
            image = cached
            return
        }

        guard !Task.isCancelled,
              let sourceData = await AppIconDataLoader.shared.data(for: url) else {
            return
        }

        // Large source artwork is downsampled off the main actor. UIKit then
        // decodes only a 96 px asset for the 44 pt list cell.
        let thumbnailData = await Task.detached(priority: .utility) {
            AppIconThumbnail.data(from: sourceData, maximumPixelSize: 96)
        }.value

        guard !Task.isCancelled,
              let thumbnailData,
              let decoded = UIImage(data: thumbnailData) else {
            return
        }

        AppIconMemoryCache.shared.insert(decoded, for: url)
        image = decoded
    }
}

/// Shared small icon bytes for download HUDs and local notification attachments.
enum NextAppIconAsset {
    @MainActor static func png(for url: URL?) async -> Data? {
        guard let url else { return nil }
        if url.isFileURL {
            return UIImage(contentsOfFile: url.path)?.pngData()
        }
        if let image = AppIconMemoryCache.shared.image(for: url) { return image.pngData() }
        guard let data = await AppIconDataLoader.shared.data(for: url) else { return nil }
        return await Task.detached(priority: .utility) {
            AppIconThumbnail.data(from: data, maximumPixelSize: 128)
        }.value
    }
}
