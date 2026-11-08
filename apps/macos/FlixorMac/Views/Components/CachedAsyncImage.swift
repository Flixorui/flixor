//
//  CachedAsyncImage.swift
//  FlixorMac
//
//  Cached async image with placeholder and error handling
//

import SwiftUI

struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL?
    let aspectRatio: CGFloat?
    let contentMode: ContentMode
    let placeholder: () -> Placeholder

    @State private var image: NSImage?
    @State private var isLoading = false
    @State private var error: Error?

    init(
        url: URL?,
        aspectRatio: CGFloat? = nil,
        contentMode: ContentMode = .fill,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.aspectRatio = aspectRatio
        self.contentMode = contentMode
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(aspectRatio, contentMode: contentMode)
                    .transition(.opacity.animation(DS.Motion.emphasized))
            } else if isLoading {
                placeholder()
                    .aspectRatio(aspectRatio, contentMode: contentMode)
            } else if error != nil {
                errorView
                    .aspectRatio(aspectRatio, contentMode: contentMode)
            } else {
                placeholder()
                    .aspectRatio(aspectRatio, contentMode: contentMode)
            }
        }
        .task(id: url) {
            await loadImage(reset: true)
        }
    }

    private var errorView: some View {
        ZStack {
            Rectangle()
                .fill(Color.gray.opacity(0.2))

            Image(systemName: "photo")
                .font(.title)
                .foregroundStyle(.gray)
        }
    }

    private func loadImage(reset: Bool = false) async {
        guard let url = url else { return }

        if reset {
            await MainActor.run {
                self.image = nil
                self.error = nil
                self.isLoading = false
            }
        }

        // Check cache first
        if let cachedImage = ImageCache.shared.get(url: url) {
            self.image = cachedImage
            return
        }

        isLoading = true

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let nsImage = NSImage(data: data) {
                // Cache the image
                ImageCache.shared.set(image: nsImage, url: url)
                await MainActor.run {
                    self.image = nsImage
                    self.isLoading = false
                }
            } else {
                throw URLError(.cannotDecodeContentData)
            }
        } catch {
            await MainActor.run {
                self.error = error
                self.isLoading = false
            }
        }
    }
}

// MARK: - Image Cache

class ImageCache {
    static let shared = ImageCache()

    private var cache = NSCache<NSURL, NSImage>()
    private let fileManager = FileManager.default
    private lazy var diskCacheURL: URL? = {
        guard let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let url = cacheDir.appendingPathComponent("ImageCache", isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private init() {
        // Configure memory cache
        cache.countLimit = 100
        cache.totalCostLimit = 100 * 1024 * 1024 // 100 MB
    }

    func get(url: URL) -> NSImage? {
        // Check memory cache
        if let image = cache.object(forKey: url as NSURL) {
            return image
        }

        // Check disk cache
        if let diskImage = getDiskImage(url: url) {
            // Add back to memory cache
            cache.setObject(diskImage, forKey: url as NSURL)
            return diskImage
        }

        return nil
    }

    func set(image: NSImage, url: URL) {
        // Save to memory cache
        cache.setObject(image, forKey: url as NSURL)

        // Save to disk cache
        Task.detached {
            await self.setDiskImage(image, url: url)
        }
    }

    func clear() {
        cache.removeAllObjects()

        if let diskCacheURL = diskCacheURL {
            try? fileManager.removeItem(at: diskCacheURL)
            try? fileManager.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
        }
    }

    // MARK: - Disk Cache

    private func getDiskImage(url: URL) -> NSImage? {
        guard let diskCacheURL = diskCacheURL else { return nil }

        let filename = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString
        let fileURL = diskCacheURL.appendingPathComponent(filename)

        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return NSImage(data: data)
    }

    private func setDiskImage(_ image: NSImage, url: URL) async {
        guard let diskCacheURL = diskCacheURL,
              let data = image.tiffRepresentation else { return }

        let filename = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString
        let fileURL = diskCacheURL.appendingPathComponent(filename)

        try? data.write(to: fileURL)
    }
}

// MARK: - Convenience Initializers

extension CachedAsyncImage where Placeholder == Color {
    init(
        url: URL?,
        aspectRatio: CGFloat? = nil,
        contentMode: ContentMode = .fill
    ) {
        self.init(
            url: url,
            aspectRatio: aspectRatio,
            contentMode: contentMode,
            placeholder: { Color.gray.opacity(0.2) }
        )
    }
}
#if DEBUG && canImport(PreviewsMacros)
#Preview {
    CachedAsyncImage(
        url: URL(string: "https://via.placeholder.com/300x450"),
        aspectRatio: 2/3
    )
    .frame(width: 200)
    .cornerRadius(DS.Radius.r8)
}
#endif
