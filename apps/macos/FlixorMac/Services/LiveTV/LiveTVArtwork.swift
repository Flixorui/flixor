//
//  LiveTVArtwork.swift
//  FlixorMac
//
//  Personal build only (FLIXOR_LIVE_TV). Loads channel logos and current
//  program artwork from the xtream-web server (`/logos/…`, `/api/image/{id}`,
//  `/api/thumbnail/{id}`), which need its session cookie.
//

#if FLIXOR_LIVE_TV
import AppKit
import SwiftUI

@MainActor
final class LiveTVArtwork {
    static let shared = LiveTVArtwork()

    private let cache = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    private var misses: [String: Date] = [:]
    private var signingIn: Task<String?, Never>?
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: config)
    }()

    private init() { cache.countLimit = 600 }

    func cached(_ path: String) -> NSImage? { cache.object(forKey: path as NSString) }

    /// `/api/thumbnail/{id}` for the airing program; refreshes every five minutes.
    static func thumbnailPath(channelId: String, title: String?) -> String {
        let bucket = Int(Date().timeIntervalSince1970 / 300)
        let t = (title ?? "").addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        return "/api/thumbnail/\(channelId)?title=\(t)&v=\(bucket)"
    }

    func load(_ path: String) async -> NSImage? {
        if let image = cached(path) { return image }
        if let miss = misses[path], Date().timeIntervalSince(miss) < 120 { return nil }
        if let task = inFlight[path] { return await task.value }
        guard let server = LiveTVStore.shared.guideServer, server.isComplete, let origin = server.origin,
              let url = URL(string: path, relativeTo: origin) else { return nil }
        let task = Task<NSImage?, Never> { [weak self] in
            guard let self else { return nil }
            for attempt in 0..<2 {
                guard let cookie = await self.cookie(forceNew: attempt > 0) else { return nil }
                var request = URLRequest(url: url)
                request.setValue("__Host-tuned-session=\(cookie)", forHTTPHeaderField: "Cookie")
                guard let (data, response) = try? await self.session.data(for: request),
                      let http = response as? HTTPURLResponse else { return nil }
                if http.statusCode == 401 { continue }
                // xtream-web's "no artwork" answer is a light SVG card; the dark tile looks better.
                let type = http.value(forHTTPHeaderField: "Content-Type") ?? ""
                guard http.statusCode == 200, type.hasPrefix("image/"), !type.contains("svg"),
                      let image = NSImage(data: data) else { return nil }
                return image
            }
            return nil
        }
        inFlight[path] = task
        let image = await task.value
        inFlight[path] = nil
        if let image { cache.setObject(image, forKey: path as NSString) } else { misses[path] = Date() }
        return image
    }

    /// One sign-in at a time for all artwork requests.
    private func cookie(forceNew: Bool) async -> String? {
        if !forceNew, let cookie = LiveTVSecrets.guideSessionCookie { return cookie }
        if let signingIn { return await signingIn.value }
        guard let server = LiveTVStore.shared.guideServer else { return nil }
        let task = Task<String?, Never> { try? await XtreamWebGuideClient(server: server).signIn() }
        signingIn = task
        let value = await task.value
        signingIn = nil
        return value
    }
}

/// An image from the xtream-web server, with a placeholder until it loads.
struct LiveTVRemoteImage<Placeholder: View>: View {
    let path: String?
    var contentMode: ContentMode = .fill
    @ViewBuilder let placeholder: () -> Placeholder
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                placeholder()
            }
        }
        .task(id: path) {
            guard let path else { image = nil; return }
            if let cached = LiveTVArtwork.shared.cached(path) { image = cached; return }
            let loaded = await LiveTVArtwork.shared.load(path)
            withAnimation(DS.Motion.standard) { image = loaded }
        }
    }
}
#endif
