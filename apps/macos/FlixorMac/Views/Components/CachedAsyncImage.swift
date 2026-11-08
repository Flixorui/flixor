//
//  CachedAsyncImage.swift
//  FlixorMac
//
//  Cached async image with placeholder and error handling
//

import CryptoKit
import ImageIO
import SwiftUI

struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL?
    let aspectRatio: CGFloat?
    let contentMode: ContentMode
    let placeholder: () -> Placeholder

    @State private var image: NSImage?
    @State private var isLoading = false
    @State private var error: Error?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        // A card recreated while scrolling draws its image in its very first frame.
        _image = State(initialValue: url.flatMap { ImageCache.shared.memoryImage(url: $0) })
    }

    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(aspectRatio, contentMode: contentMode)
                    .transition(.opacity)
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
        guard let url else {
            image = nil
            error = nil
            isLoading = false
            return
        }

        if let cached = ImageCache.shared.memoryImage(url: url) {
            image = cached
            error = nil
            isLoading = false
            return
        }

        // The previous image stays up until its replacement is ready.
        isLoading = image == nil
        do {
            let result = try await ImageCache.shared.load(url: url)
            guard !Task.isCancelled else { return }
            error = nil
            isLoading = false
            // Only a real download fades in; cached artwork just appears.
            if result.fromNetwork && !reduceMotion {
                withAnimation(.easeOut(duration: 0.2)) { image = result.image }
            } else {
                image = result.image
            }
        } catch {
            guard !Task.isCancelled else { return }
            self.error = error
            isLoading = false
        }
    }
}

// MARK: - Image Cache

/// Decoded artwork in memory, original files on disk. Decoding and disk access
/// stay off the main thread, so scrolling never waits on them.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    struct LoadResult: Sendable {
        let image: NSImage
        let fromNetwork: Bool
    }

    /// One load per URL, and it finishes even if the card scrolls away.
    private actor LoadCoordinator {
        private var tasks: [URL: Task<LoadResult, Error>] = [:]

        func load(_ url: URL, using fetch: @escaping @Sendable () async throws -> LoadResult) async throws -> LoadResult {
            if let task = tasks[url] { return try await task.value }
            let task = Task.detached(priority: .userInitiated, operation: fetch)
            tasks[url] = task
            defer { tasks[url] = nil }
            return try await task.value
        }
    }

    private let memory = NSCache<NSURL, NSImage>()
    private let coordinator = LoadCoordinator()
    private let fileManager = FileManager.default
    private let maxPixelSize = 2560
    private let maxDiskBytes = 2 * 1024 * 1024 * 1024

    private lazy var diskCacheURL: URL? = {
        guard let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let url = cacheDir.appendingPathComponent("ImageCacheV2", isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private init() {
        // A Home screen holds hundreds of posters, so the budget has to cover them all.
        memory.countLimit = 4000
        memory.totalCostLimit = Int(min(1_500_000_000, ProcessInfo.processInfo.physicalMemory / 6))

        Task.detached(priority: .background) { [self] in
            removeLegacyDiskCache()
            trimDiskCache()
        }
    }

    /// Already-decoded image only. Safe to call while building a view.
    func memoryImage(url: URL) -> NSImage? {
        memory.object(forKey: url as NSURL)
    }

    /// Memory, then disk. Reads a file, so don't call it on the main thread.
    func get(url: URL) -> NSImage? {
        if let image = memoryImage(url: url) { return image }
        guard let data = diskData(for: url), let image = decode(data) else { return nil }
        store(image, url: url)
        return image
    }

    func load(url: URL) async throws -> LoadResult {
        if let image = memoryImage(url: url) { return LoadResult(image: image, fromNetwork: false) }
        return try await coordinator.load(url) { [self] in
            if let image = get(url: url) { return LoadResult(image: image, fromNetwork: false) }

            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = decode(data) else { throw URLError(.cannotDecodeContentData) }
            store(image, url: url)
            writeDiskData(data, for: url)
            return LoadResult(image: image, fromNetwork: true)
        }
    }

    /// Loads artwork ahead of time, a few at once, so rows are ready before they appear.
    func preheat(urls: [URL]) async {
        await withTaskGroup(of: Void.self) { group in
            var running = 0
            for url in urls where memoryImage(url: url) == nil {
                if running >= 6 {
                    await group.next()
                    running -= 1
                }
                group.addTask(priority: .utility) { [self] in _ = try? await load(url: url) }
                running += 1
            }
        }
    }

    func clear() {
        memory.removeAllObjects()

        if let diskCacheURL {
            try? fileManager.removeItem(at: diskCacheURL)
            try? fileManager.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
        }
    }

    private func store(_ image: NSImage, url: URL) {
        let cost = image.representations.first.map { $0.pixelsWide * $0.pixelsHigh * 4 } ?? 0
        memory.setObject(image, forKey: url as NSURL, cost: cost)
    }

    /// Decodes now rather than on first draw, and caps very large originals.
    private func decode(_ data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return NSImage(data: data)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(max(width, height), maxPixelSize),
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return NSImage(data: data)
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    // MARK: - Disk Cache

    private func diskFileURL(for url: URL) -> URL? {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return diskCacheURL?.appendingPathComponent(digest.map { String(format: "%02x", $0) }.joined())
    }

    private func diskData(for url: URL) -> Data? {
        diskFileURL(for: url).flatMap { try? Data(contentsOf: $0) }
    }

    private func writeDiskData(_ data: Data, for url: URL) {
        guard let file = diskFileURL(for: url) else { return }
        try? data.write(to: file, options: .atomic)
    }

    /// The old cache stored uncompressed TIFFs and can be very large.
    private func removeLegacyDiskCache() {
        guard let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        try? fileManager.removeItem(at: cacheDir.appendingPathComponent("ImageCache", isDirectory: true))
    }

    /// Keeps the disk cache bounded, removing the oldest files first.
    private func trimDiskCache() {
        guard let diskCacheURL,
              let files = try? fileManager.contentsOfDirectory(
                at: diskCacheURL,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
              ) else { return }

        var entries = files.compactMap { file -> (url: URL, size: Int, date: Date)? in
            guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
            return (file, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }
        var total = entries.reduce(0) { $0 + $1.size }
        guard total > maxDiskBytes else { return }

        entries.sort { $0.date < $1.date }
        for entry in entries where total > maxDiskBytes {
            try? fileManager.removeItem(at: entry.url)
            total -= entry.size
        }
    }
}

// MARK: - Resolved Artwork

/// TMDB artwork URLs already looked up this session, so a card scrolled back into
/// view shows its final image at once instead of looking it up and swapping again.
@MainActor
final class ResolvedArtworkCache {
    static let shared = ResolvedArtworkCache()

    private var urls: [String: URL] = [:]
    private var resolved: Set<String> = []

    func url(for key: String) -> URL? { urls[key] }

    func isResolved(_ key: String) -> Bool { resolved.contains(key) }

    func store(_ url: URL?, for key: String) {
        resolved.insert(key)
        if let url { urls[key] = url }
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
            placeholder: { Color.white.opacity(0.05) }
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
