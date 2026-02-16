//
//  CachedAsyncImage.swift
//  FlixorTV
//
//  Cached async image with placeholder and error handling.
//

import SwiftUI
import UIKit
import CryptoKit

struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL?
    let aspectRatio: CGFloat?
    let contentMode: ContentMode
    let showsErrorView: Bool
    let placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var error: Error?
    @State private var loadedURL: URL?

    init(
        url: URL?,
        aspectRatio: CGFloat? = nil,
        contentMode: ContentMode = .fill,
        showsErrorView: Bool = true,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.aspectRatio = aspectRatio
        self.contentMode = contentMode
        self.showsErrorView = showsErrorView
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(aspectRatio, contentMode: contentMode)
                    .transition(.opacity.animation(.easeInOut(duration: 0.3)))
            } else if isLoading {
                placeholder()
                    .aspectRatio(aspectRatio, contentMode: contentMode)
            } else if error != nil, showsErrorView {
                errorView
                    .aspectRatio(aspectRatio, contentMode: contentMode)
            } else {
                placeholder()
                    .aspectRatio(aspectRatio, contentMode: contentMode)
            }
        }
        .task(id: url) {
            await loadImage()
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

    private func loadImage() async {
        guard let url = url else {
            await MainActor.run {
                self.image = nil
                self.loadedURL = nil
                self.error = nil
                self.isLoading = false
            }
            return
        }

        // Keep currently rendered image when task re-runs for same URL.
        if loadedURL == url, image != nil {
            return
        }

        if let cachedImage = await Task.detached(priority: .userInitiated, operation: {
            ImageCache.shared.get(url: url)
        }).value {
            await MainActor.run {
                self.image = cachedImage
                self.loadedURL = url
                self.error = nil
                self.isLoading = false
            }
            return
        }

        await MainActor.run {
            // Only clear image if the URL changed and we don't have a cache hit.
            if self.loadedURL != url {
                self.image = nil
                self.loadedURL = nil
            }
            self.error = nil
            self.isLoading = true
        }

        do {
            let data = try await ImageRequestCoordinator.shared.data(for: url)
            let decodedImage = try await Task.detached(priority: .userInitiated) {
                guard let uiImage = UIImage(data: data) else {
                    throw URLError(.cannotDecodeContentData)
                }
                return uiImage
            }.value

            await Task.detached(priority: .utility) {
                ImageCache.shared.set(image: decodedImage, url: url, rawData: data)
            }.value

            await MainActor.run {
                self.image = decodedImage
                self.loadedURL = url
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error
                self.isLoading = false
            }
        }
    }
}

final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private var cache = NSCache<NSURL, UIImage>()
    private let fileManager = FileManager.default
    private let diskCacheURL: URL?

    private init() {
        cache.countLimit = 400
        cache.totalCostLimit = 300 * 1024 * 1024

        if let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let url = cacheDir.appendingPathComponent("ImageCache", isDirectory: true)
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            diskCacheURL = url
        } else {
            diskCacheURL = nil
        }
    }

    /// Hash URL to a fixed-length, filesystem-safe filename.
    private func cacheFilename(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func get(url: URL) -> UIImage? {
        if let image = cache.object(forKey: url as NSURL) {
            return image
        }

        if let diskImage = getDiskImage(url: url) {
            cache.setObject(diskImage, forKey: url as NSURL)
            return diskImage
        }

        return nil
    }

    func set(image: UIImage, url: URL) {
        set(image: image, url: url, rawData: nil)
    }

    func set(image: UIImage, url: URL, rawData: Data?) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: url as NSURL, cost: cost)

        Task.detached {
            await self.setDiskImage(image, url: url, rawData: rawData)
        }
    }

    func clear() {
        cache.removeAllObjects()

        if let diskCacheURL = diskCacheURL {
            try? fileManager.removeItem(at: diskCacheURL)
            try? fileManager.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
        }
    }

    private func getDiskImage(url: URL) -> UIImage? {
        guard let diskCacheURL = diskCacheURL else { return nil }

        let filename = cacheFilename(for: url)
        let fileURL = diskCacheURL.appendingPathComponent(filename)

        guard let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]) else { return nil }
        return UIImage(data: data)
    }

    private func setDiskImage(_ image: UIImage, url: URL, rawData: Data?) async {
        guard let diskCacheURL = diskCacheURL else { return }

        let data = rawData ?? image.jpegData(compressionQuality: 0.85)
        guard let data = data else { return }

        let filename = cacheFilename(for: url)
        let fileURL = diskCacheURL.appendingPathComponent(filename)

        try? data.write(to: fileURL)
    }
}

actor ImageRequestCoordinator {
    static let shared = ImageRequestCoordinator()

    private var inFlight: [URL: Task<Data, Error>] = [:]
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(
            memoryCapacity: 128 * 1024 * 1024,
            diskCapacity: 512 * 1024 * 1024
        )
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    func data(for url: URL) async throws -> Data {
        if let task = inFlight[url] {
            return try await task.value
        }

        let task = Task<Data, Error> {
            let (data, _) = try await session.data(from: url)
            return data
        }
        inFlight[url] = task
        defer { inFlight[url] = nil }
        return try await task.value
    }
}

extension CachedAsyncImage where Placeholder == Color {
    init(
        url: URL?,
        aspectRatio: CGFloat? = nil,
        contentMode: ContentMode = .fill,
        showsErrorView: Bool = true
    ) {
        self.init(
            url: url,
            aspectRatio: aspectRatio,
            contentMode: contentMode,
            showsErrorView: showsErrorView,
            placeholder: { Color.gray.opacity(0.2) }
        )
    }
}

#if DEBUG && canImport(PreviewsMacros)
#Preview {
    CachedAsyncImage(
        url: URL(string: "https://via.placeholder.com/300x450"),
        aspectRatio: 2 / 3
    )
    .frame(width: 200)
    .cornerRadius(8)
}
#endif
