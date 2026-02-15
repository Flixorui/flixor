//
//  CachedAsyncImage.swift
//  FlixorTV
//
//  Cached async image with placeholder and error handling.
//

import SwiftUI
import UIKit

struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL?
    let aspectRatio: CGFloat?
    let contentMode: ContentMode
    let showsErrorView: Bool
    let placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var error: Error?

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

        if let cachedImage = ImageCache.shared.get(url: url) {
            await MainActor.run {
                self.image = cachedImage
            }
            return
        }

        await MainActor.run {
            self.isLoading = true
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let uiImage = UIImage(data: data) else {
                throw URLError(.cannotDecodeContentData)
            }

            ImageCache.shared.set(image: uiImage, url: url)
            await MainActor.run {
                self.image = uiImage
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

final class ImageCache {
    static let shared = ImageCache()

    private var cache = NSCache<NSURL, UIImage>()
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
        cache.countLimit = 100
        cache.totalCostLimit = 100 * 1024 * 1024
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
        cache.setObject(image, forKey: url as NSURL)

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

    private func getDiskImage(url: URL) -> UIImage? {
        guard let diskCacheURL = diskCacheURL else { return nil }

        let filename = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString
        let fileURL = diskCacheURL.appendingPathComponent(filename)

        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: data)
    }

    private func setDiskImage(_ image: UIImage, url: URL) async {
        guard let diskCacheURL = diskCacheURL else { return }

        let data = image.pngData() ?? image.jpegData(compressionQuality: 0.9)
        guard let data = data else { return }

        let filename = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString
        let fileURL = diskCacheURL.appendingPathComponent(filename)

        try? data.write(to: fileURL)
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
