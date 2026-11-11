//
//  CachedAsyncImage.swift
//  FlixorMac
//
//  Cached async image with placeholder and error handling
//

import CryptoKit
import FlixorKit
import ImageIO
import SwiftUI

struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL?
    let aspectRatio: CGFloat?
    let contentMode: ContentMode
    /// Longest side, in pixels, the image is decoded to. nil keeps the 2560 px cap.
    let maxPixelSize: Int?
    let placeholder: () -> Placeholder

    @State private var image: NSImage?
    @State private var isLoading = false
    @State private var error: Error?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        url: URL?,
        aspectRatio: CGFloat? = nil,
        contentMode: ContentMode = .fill,
        maxPixelSize: Int? = nil,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.aspectRatio = aspectRatio
        self.contentMode = contentMode
        self.maxPixelSize = maxPixelSize
        self.placeholder = placeholder
        // A card recreated while scrolling draws its image in its very first frame.
        _image = State(initialValue: url.flatMap { ImageCache.shared.memoryImage(url: $0, maxPixelSize: maxPixelSize) })
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
        // A new size bucket (the card grew) loads a larger decode too.
        .task(id: LoadKey(url: url, bucket: ImageCache.sizeBucket(for: maxPixelSize))) {
            await loadImage()
        }
    }

    private struct LoadKey: Equatable {
        let url: URL?
        let bucket: Int
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

        if let cached = ImageCache.shared.memoryImage(url: url, maxPixelSize: maxPixelSize) {
            image = cached
            error = nil
            isLoading = false
            return
        }

        // The previous image stays up until its replacement is ready.
        isLoading = image == nil
        do {
            let result = try await ImageCache.shared.load(url: url, maxPixelSize: maxPixelSize)
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

// MARK: - Async Limiter

/// Lets at most `limit` callers run at once; the rest wait their turn.
fileprivate actor AsyncLimiter {
    private let limit: Int
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
    }

    func acquire() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            running -= 1
        } else {
            // The slot passes straight to the next waiter.
            waiters.removeFirst().resume()
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

    private struct FileData: Sendable {
        let data: Data
        let fromNetwork: Bool
    }

    /// One task per key, and it finishes even if the card scrolls away.
    private actor TaskCoalescer<Value: Sendable> {
        private var tasks: [String: Task<Value, Error>] = [:]

        func run(_ key: String, priority: TaskPriority, _ operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
            if let task = tasks[key] { return try await task.value }
            let task = Task.detached(priority: priority, operation: operation)
            tasks[key] = task
            defer { tasks[key] = nil }
            return try await task.value
        }
    }

    /// Decoded sizes kept in memory. A request rounds up to the next bucket, and a
    /// larger decoded copy serves any smaller request.
    private static let sizeBuckets = [256, 512, 768, 1024, 1536, 2560]
    private static let maxPixelSize = 2560

    private let memory = NSCache<NSString, NSImage>()
    private let decodes = TaskCoalescer<LoadResult>()
    private let downloads = TaskCoalescer<FileData>()
    private let decodeLimiter = AsyncLimiter(limit: 3)
    private let fileManager = FileManager.default
    private let maxDiskBytes = 2 * 1024 * 1024 * 1024
    /// Trim the disk cache again after this much has been written.
    private let trimAfterBytes = 200 * 1024 * 1024
    private let diskQueue = DispatchQueue(label: "ImageCache.disk", qos: .utility)
    private let trimLock = NSLock()
    private var bytesSinceTrim = 0
    private var isTrimming = false

    /// Images get their own connection pool, so they never queue behind API calls.
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.httpMaximumConnectionsPerHost = 6
        // Files are kept in the disk cache below; no second copy in URLCache.
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration)
    }()

    // A constant, not `lazy`: loads read it from many threads at once, and a
    // lazy var's first initialization races (crashed in swift_getObjectType).
    private let diskCacheURL: URL? = {
        let fileManager = FileManager.default
        guard let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let url = cacheDir.appendingPathComponent("ImageCacheV2", isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private init() {
        // Cards decode at their own size, so a few hundred MB covers a full Home screen.
        memory.countLimit = 4000
        memory.totalCostLimit = Int(min(400_000_000, ProcessInfo.processInfo.physicalMemory / 8))

        diskQueue.async { [self] in
            removeLegacyDiskCache()
            trimDiskCache()
        }
    }

    /// Longest side, in pixels, an image needs to fill a frame of `width` x `height`
    /// points at 2x, for any shape from a 2:3 poster to a 16:9 backdrop.
    static func fillPixelSize(width: CGFloat, height: CGFloat) -> Int {
        let pixelWidth = width * 2
        let pixelHeight = height * 2
        let landscape = max(pixelWidth, pixelHeight * 16 / 9)
        let portrait = max(pixelHeight, pixelWidth * 3 / 2)
        return Int(max(landscape, portrait).rounded(.up))
    }

    /// The decode size a request rounds up to.
    static func sizeBucket(for maxPixelSize: Int?) -> Int {
        bucket(for: maxPixelSize)
    }

    private static func bucket(for maxPixelSize: Int?) -> Int {
        guard let maxPixelSize, maxPixelSize > 0 else { return Self.maxPixelSize }
        return sizeBuckets.first { $0 >= maxPixelSize } ?? Self.maxPixelSize
    }

    private static func memoryKey(_ url: URL, bucket: Int) -> NSString {
        "\(bucket)|\(url.absoluteString)" as NSString
    }

    /// Already-decoded image only. Safe to call while building a view.
    func memoryImage(url: URL, maxPixelSize: Int? = nil) -> NSImage? {
        memoryImage(url: url, bucket: Self.bucket(for: maxPixelSize))
    }

    private func memoryImage(url: URL, bucket: Int) -> NSImage? {
        for size in Self.sizeBuckets where size >= bucket {
            if let image = memory.object(forKey: Self.memoryKey(url, bucket: size)) { return image }
        }
        return nil
    }

    /// Memory, then disk. Reads a file, so don't call it on the main thread.
    func get(url: URL, maxPixelSize: Int? = nil) -> NSImage? {
        let bucket = Self.bucket(for: maxPixelSize)
        if let image = memoryImage(url: url, bucket: bucket) { return image }
        guard let data = diskData(for: url) else { return nil }
        guard let image = decode(data, maxPixelSize: bucket) else {
            removeDiskData(for: url)
            return nil
        }
        store(image, url: url, bucket: bucket)
        return image
    }

    func load(url: URL, maxPixelSize: Int? = nil) async throws -> LoadResult {
        try await load(url: url, maxPixelSize: maxPixelSize, isPreheat: false)
    }

    private func load(url: URL, maxPixelSize: Int?, isPreheat: Bool) async throws -> LoadResult {
        let bucket = Self.bucket(for: maxPixelSize)
        if let image = memoryImage(url: url, bucket: bucket) { return LoadResult(image: image, fromNetwork: false) }

        let key = Self.memoryKey(url, bucket: bucket) as String
        return try await decodes.run(key, priority: isPreheat ? .utility : .userInitiated) { [self] in
            if let image = memoryImage(url: url, bucket: bucket) { return LoadResult(image: image, fromNetwork: false) }

            let file = try await fileData(for: url, isPreheat: isPreheat)
            await decodeLimiter.acquire()
            let image = decode(file.data, maxPixelSize: bucket)
            await decodeLimiter.release()
            guard let image else {
                // A damaged cached file: drop it so the next load downloads it again.
                if !file.fromNetwork { removeDiskData(for: url) }
                throw URLError(.cannotDecodeContentData)
            }
            store(image, url: url, bucket: bucket)
            return LoadResult(image: image, fromNetwork: file.fromNetwork)
        }
    }

    /// The original bytes, from disk or the network; one download per URL.
    private func fileData(for url: URL, isPreheat: Bool) async throws -> FileData {
        try await downloads.run(url.absoluteString, priority: isPreheat ? .utility : .userInitiated) { [self] in
            if let data = diskData(for: url) { return FileData(data: data, fromNetwork: false) }

            let data = try await download(url, priority: isPreheat ? URLSessionTask.lowPriority : URLSessionTask.highPriority)
            // Only image data goes to disk, so an error page is never cached.
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  CGImageSourceGetType(source) != nil else {
                throw URLError(.cannotDecodeContentData)
            }
            writeDiskData(data, for: url)
            return FileData(data: data, fromNetwork: true)
        }
    }

    private func download(_ url: URL, priority: Float) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: url) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }
                guard let data, !data.isEmpty else {
                    continuation.resume(throwing: URLError(.zeroByteResource))
                    return
                }
                continuation.resume(returning: data)
            }
            task.priority = priority
            task.resume()
        }
    }

    /// Loads artwork ahead of time, a few at once, so rows are ready before they appear.
    /// Runs below on-screen loads.
    func preheat(urls: [URL], maxPixelSize: Int? = nil) async {
        await withTaskGroup(of: Void.self) { group in
            var running = 0
            for url in urls where memoryImage(url: url, maxPixelSize: maxPixelSize) == nil {
                if running >= 6 {
                    await group.next()
                    running -= 1
                }
                group.addTask(priority: .utility) { [self] in
                    _ = try? await load(url: url, maxPixelSize: maxPixelSize, isPreheat: true)
                }
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

    private func store(_ image: NSImage, url: URL, bucket: Int) {
        let cost = image.representations.first.map { $0.pixelsWide * $0.pixelsHigh * 4 } ?? 0
        memory.setObject(image, forKey: Self.memoryKey(url, bucket: bucket), cost: cost)
    }

    /// Decodes now rather than on first draw, scaled down to `maxPixelSize` on the longest side.
    private func decode(_ data: Data, maxPixelSize: Int) -> NSImage? {
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
        guard let file = diskFileURL(for: url), let data = try? Data(contentsOf: file) else { return nil }
        markUsed(file)
        return data
    }

    /// Trimming removes the oldest modification dates first, so a file in use
    /// gets a fresh date (at most once a day).
    private func markUsed(_ file: URL) {
        let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let date, Date().timeIntervalSince(date) < 86_400 { return }
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
    }

    private func removeDiskData(for url: URL) {
        guard let file = diskFileURL(for: url) else { return }
        try? fileManager.removeItem(at: file)
    }

    private func writeDiskData(_ data: Data, for url: URL) {
        guard let file = diskFileURL(for: url) else { return }
        guard (try? data.write(to: file, options: .atomic)) != nil else { return }
        noteDiskWrite(data.count)
    }

    private func noteDiskWrite(_ bytes: Int) {
        trimLock.lock()
        bytesSinceTrim += bytes
        let shouldTrim = bytesSinceTrim >= trimAfterBytes && !isTrimming
        if shouldTrim {
            bytesSinceTrim = 0
            isTrimming = true
        }
        trimLock.unlock()
        guard shouldTrim else { return }

        diskQueue.async { [self] in
            trimDiskCache()
            trimLock.lock()
            isTrimming = false
            trimLock.unlock()
        }
    }

    /// The old cache stored uncompressed TIFFs and can be very large.
    private func removeLegacyDiskCache() {
        guard let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        try? fileManager.removeItem(at: cacheDir.appendingPathComponent("ImageCache", isDirectory: true))
    }

    /// Keeps the disk cache bounded, removing the least recently used files first.
    /// Trims to 90% of the cap so it doesn't run again right away.
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

        let target = maxDiskBytes / 10 * 9
        entries.sort { $0.date < $1.date }
        for entry in entries where total > target {
            try? fileManager.removeItem(at: entry.url)
            total -= entry.size
        }
    }
}

// MARK: - Resolved Artwork

/// TMDB artwork URLs already looked up, so a card shows its final image at once
/// instead of looking it up and swapping again. Results are saved to disk, so a
/// relaunch repeats none of the lookups.
@MainActor
final class ResolvedArtworkCache {
    static let shared = ResolvedArtworkCache()

    private struct Entry: Codable, Sendable {
        let url: URL?
        let date: Date
    }

    /// Found artwork rarely changes; a title with none is checked again sooner.
    private static let foundLifetime: TimeInterval = 60 * 60 * 24 * 30
    private static let missingLifetime: TimeInterval = 60 * 60 * 24

    private static let fileURL: URL? = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("ResolvedArtwork.json")

    private static let saveQueue = DispatchQueue(label: "ResolvedArtworkCache.save", qos: .utility)

    private var entries: [String: Entry]
    /// Lookups that failed this session (offline, server error). Not saved.
    private var failed: Set<String> = []
    private var inFlight: [String: Task<URL?, Never>] = [:]
    private let limiter = AsyncLimiter(limit: 6)
    private var saveTask: Task<Void, Never>?

    private init() {
        entries = Self.loadEntries()
    }

    /// The resolved URL, even if it's due for a refresh. Safe to call while building a view.
    func url(for key: String) -> URL? { entries[key]?.url }

    func isResolved(_ key: String) -> Bool {
        if failed.contains(key) { return true }
        guard let entry = entries[key] else { return false }
        let lifetime = entry.url == nil ? Self.missingLifetime : Self.foundLifetime
        return Date().timeIntervalSince(entry.date) < lifetime
    }

    func store(_ url: URL?, for key: String) {
        entries[key] = Entry(url: url, date: Date())
        scheduleSave()
    }

    /// Runs `lookup` once per key (a few keys at a time) and remembers the answer.
    func resolve(_ key: String, lookup: @escaping @MainActor () async throws -> URL?) async -> URL? {
        if isResolved(key) { return entries[key]?.url }
        if let task = inFlight[key] { return await task.value }

        let limiter = limiter
        let task = Task { () -> URL? in
            await limiter.acquire()
            let result: Result<URL?, Error>
            do {
                result = .success(try await lookup())
            } catch {
                result = .failure(error)
            }
            await limiter.release()

            inFlight[key] = nil
            switch result {
            case .success(let url):
                store(url, for: key)
                return url
            case .failure(let error):
                // Cancelled (or not connected yet): nothing learned, try again next time.
                if !(error is CancellationError) { failed.insert(key) }
                return entries[key]?.url
            }
        }
        inFlight[key] = task
        return await task.value
    }

    private static func loadEntries() -> [String: Entry] {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        let cutoff = Date().addingTimeInterval(-foundLifetime * 2)
        return decoded.filter { $0.value.date > cutoff }
    }

    private func scheduleSave() {
        guard saveTask == nil else { return }
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            saveTask = nil
            guard let fileURL = Self.fileURL else { return }
            let snapshot = entries
            Self.saveQueue.async {
                guard let data = try? JSONEncoder().encode(snapshot) else { return }
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }
}

// MARK: - Artwork Lookup

/// Finds TMDB artwork for library items. Shared by the cards, so the same title
/// is looked up once, and kept in ResolvedArtworkCache.
@MainActor
enum ArtworkLookup {
    enum Kind: String {
        /// Best backdrop: English (title text) first, then any language, then textless.
        case backdrop
        /// The poster from the title's TMDB details.
        case poster
        /// Best-voted poster from TMDB images, English first.
        case imagesPoster
    }

    private struct TMDBRef {
        let mediaType: String
        let id: Int
    }

    /// The cache key, or nil for items with nothing to look up.
    static func key(_ kind: Kind, for item: MediaItem) -> String? {
        guard let subject = subject(kind, for: item) else { return nil }
        if subject.hasPrefix("tmdb:") { return "\(kind.rawValue):\(subject)" }
        // Plex rating keys are per server.
        let server = FlixorCore.shared.currentServer?.id ?? "-"
        return "\(kind.rawValue):\(server):\(subject)"
    }

    /// Already-resolved URL, without a lookup. Safe to call while building a view.
    static func cachedURL(_ kind: Kind, for item: MediaItem) -> URL? {
        key(kind, for: item).flatMap { ResolvedArtworkCache.shared.url(for: $0) }
    }

    static func resolve(_ kind: Kind, for item: MediaItem) async -> URL? {
        guard let key = key(kind, for: item), let subject = subject(kind, for: item) else { return nil }
        // The server the key was built for; its answer is dropped if the server changes meanwhile.
        let serverID = FlixorCore.shared.currentServer?.id
        let plexServer = FlixorCore.shared.plexServer
        return await ResolvedArtworkCache.shared.resolve(key) {
            guard let ref = try await tmdbRef(subject: subject, showForSeasons: kind == .backdrop, plexServer: plexServer) else {
                return try answer(nil, subject: subject, serverID: serverID)
            }
            let url: URL?
            switch kind {
            case .backdrop: url = try await bestBackdrop(ref)
            case .poster: url = try await detailsPoster(ref)
            case .imagesPoster: url = try await bestPoster(ref)
            }
            return try answer(url, subject: subject, serverID: serverID)
        }
    }

    /// Throws (so nothing is stored) when a Plex answer arrives after a server switch.
    private static func answer(_ url: URL?, subject: String, serverID: String?) throws -> URL? {
        if !subject.hasPrefix("tmdb:"), FlixorCore.shared.currentServer?.id != serverID {
            throw CancellationError()
        }
        return url
    }

    /// The tmdb id or Plex rating key whose artwork stands for the item: the
    /// show's for episodes (and for seasons, for backdrops).
    private static func subject(_ kind: Kind, for item: MediaItem) -> String? {
        if item.id.hasPrefix("tmdb:") { return item.id }
        if item.type == "episode", let showKey = item.grandparentRatingKey { return showKey }
        if kind == .backdrop, item.type == "season", let showKey = item.parentRatingKey { return showKey }
        if item.id.hasPrefix("plex:") { return String(item.id.dropFirst(5)) }
        if !item.id.isEmpty, item.id.allSatisfy({ $0.isNumber }) { return item.id }
        return nil
    }

    private static func tmdbRef(subject: String, showForSeasons: Bool, plexServer: PlexServerService?) async throws -> TMDBRef? {
        if subject.hasPrefix("tmdb:") {
            let parts = subject.split(separator: ":")
            guard parts.count == 3, let id = Int(parts[2]) else { return nil }
            return TMDBRef(mediaType: parts[1] == "movie" ? "movie" : "tv", id: id)
        }

        // Not connected yet is not an answer; don't remember it.
        guard let plexServer else { throw CancellationError() }
        let meta = try await plexServer.getMetadata(ratingKey: subject)

        if meta.type == "episode", let showKey = meta.grandparentRatingKey {
            return try await tmdbRef(subject: showKey, showForSeasons: showForSeasons, plexServer: plexServer)
        }
        if showForSeasons, meta.type == "season", let showKey = meta.parentRatingKey {
            return try await tmdbRef(subject: showKey, showForSeasons: showForSeasons, plexServer: plexServer)
        }

        guard let guid = meta.guids.first(where: { $0.contains("tmdb://") || $0.contains("themoviedb://") }),
              let id = guid.components(separatedBy: "://").last.flatMap({ Int($0) }) else { return nil }
        return TMDBRef(mediaType: meta.type == "movie" ? "movie" : "tv", id: id)
    }

    private static func topVoted(_ images: [FlixorKit.TMDBImage]) -> FlixorKit.TMDBImage? {
        images.sorted { ($0.voteAverage ?? 0) > ($1.voteAverage ?? 0) }.first
    }

    private static func bestBackdrop(_ ref: TMDBRef) async throws -> URL? {
        let backdrops = try await FlixorCore.shared.tmdb.getImages(mediaType: ref.mediaType, id: ref.id).backdrops
        let path = topVoted(backdrops.filter { $0.iso6391 == "en" })?.filePath
            ?? topVoted(backdrops.filter { $0.iso6391 != nil })?.filePath
            ?? topVoted(backdrops)?.filePath
        return path.flatMap { URL(string: "https://image.tmdb.org/t/p/w780\($0)") }
    }

    private static func bestPoster(_ ref: TMDBRef) async throws -> URL? {
        let posters = try await FlixorCore.shared.tmdb.getImages(mediaType: ref.mediaType, id: ref.id).posters
        let english = posters.filter { $0.iso6391 == "en" }
        let path = topVoted(english.isEmpty ? posters : english)?.filePath
        return path.flatMap { URL(string: "https://image.tmdb.org/t/p/w500\($0)") }
    }

    private static func detailsPoster(_ ref: TMDBRef) async throws -> URL? {
        let path: String?
        if ref.mediaType == "movie" {
            path = try await FlixorCore.shared.tmdb.getMovieDetails(id: ref.id).posterPath
        } else {
            path = try await FlixorCore.shared.tmdb.getTVDetails(id: ref.id).posterPath
        }
        return path.flatMap { URL(string: "https://image.tmdb.org/t/p/w500\($0)") }
    }
}

// MARK: - Convenience Initializers

extension CachedAsyncImage where Placeholder == Color {
    init(
        url: URL?,
        aspectRatio: CGFloat? = nil,
        contentMode: ContentMode = .fill,
        maxPixelSize: Int? = nil
    ) {
        self.init(
            url: url,
            aspectRatio: aspectRatio,
            contentMode: contentMode,
            maxPixelSize: maxPixelSize,
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
