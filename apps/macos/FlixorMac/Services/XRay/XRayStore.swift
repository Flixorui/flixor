//
//  XRayStore.swift
//  FlixorMac
//
//  What X-Ray keeps on this Mac: each title's cast and timeline, and each actor's face
//  references made from their TMDB profile photos (shared by every title they're in).
//  Application Support/Flixor/XRay. Nothing leaves the Mac; TMDB is only asked for the
//  cast list and photos, like the Details page does.
//

import Foundation
import CoreGraphics
import ImageIO
import FlixorKit

/// The TMDB title X-Ray works on.
struct XRayIdentity: Hashable {
    let tmdbId: Int
    let isMovie: Bool
    let season: Int?
    let episode: Int?

    var key: String {
        if isMovie { return "movie-\(tmdbId)" }
        if let season, let episode { return "tv-\(tmdbId)-s\(season)e\(episode)" }
        return "tv-\(tmdbId)"
    }
}

actor XRayStore {
    static let shared = XRayStore()

    /// Top-billed cast members to match against. More means slower and more confusable.
    static let castLimit = 20
    static let guestLimit = 10
    static let photosPerPerson = 6
    private static let referenceVersion = 1

    private let base: URL
    private var engine: XRayFaceEngine?
    private var engineLoaded = false

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        base = support.appendingPathComponent("Flixor/XRay", isDirectory: true)
        try? FileManager.default.createDirectory(at: base.appendingPathComponent("faces"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: base.appendingPathComponent("titles"), withIntermediateDirectories: true)
    }

    // MARK: Cast

    func cast(for identity: XRayIdentity) async -> [XRayCastMember] {
        let tmdb = await FlixorCore.shared.tmdb
        var members: [TMDBCastMember] = []
        if identity.isMovie {
            members = (try? await tmdb.getMovieCredits(id: identity.tmdbId).cast) ?? []
            members = Array(members.prefix(Self.castLimit))
        } else {
            if let season = identity.season, let episode = identity.episode,
               let credits = try? await tmdb.getEpisodeCredits(tvId: identity.tmdbId, season: season, episode: episode) {
                members = Array(credits.cast.prefix(Self.castLimit)) + Array((credits.guestStars ?? []).prefix(Self.guestLimit))
            }
            if members.isEmpty {
                members = Array(((try? await tmdb.getTVCredits(id: identity.tmdbId).cast) ?? []).prefix(Self.castLimit))
            }
        }
        var seen = Set<Int>()
        return members.enumerated().compactMap { index, m in
            guard seen.insert(m.id).inserted else { return nil }
            return XRayCastMember(id: m.id, name: m.name, character: m.character?.nilIfEmpty, profilePath: m.profilePath, order: index)
        }
    }

    // MARK: Face references

    /// Face embeddings per cast member (cached per person). Members whose photos show no
    /// usable face are left out.
    func references(for cast: [XRayCastMember]) async -> [Int: [[Float]]] {
        guard let engine = loadEngine() else { return [:] }
        var out: [Int: [[Float]]] = [:]
        for member in cast {
            if Task.isCancelled { break }
            if let cached = cachedFaces(member.id) {
                if !cached.isEmpty { out[member.id] = cached }
                continue
            }
            let faces = await makeFaces(for: member.id, engine: engine)
            saveFaces(faces, for: member.id)
            if !faces.isEmpty { out[member.id] = faces }
        }
        return out
    }

    private func makeFaces(for personId: Int, engine: XRayFaceEngine) async -> [[Float]] {
        let tmdb = await FlixorCore.shared.tmdb
        guard let images = try? await tmdb.getPersonImages(id: personId) else { return [] }
        var faces: [[Float]] = []
        for profile in images.profiles.prefix(Self.photosPerPerson) {
            guard let url = TMDBImageURL.url(profile.filePath, size: .h632),
                  let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  let face = engine.largestFaceEmbedding(in: image) else { continue }
            faces.append(face)
        }
        return faces
    }

    private struct FaceFile: Codable {
        let version: Int
        let faces: [[Float]]
    }

    private func facesURL(_ id: Int) -> URL { base.appendingPathComponent("faces/\(id).json") }

    private func cachedFaces(_ id: Int) -> [[Float]]? {
        guard let data = try? Data(contentsOf: facesURL(id)),
              let file = try? JSONDecoder().decode(FaceFile.self, from: data),
              file.version == Self.referenceVersion else { return nil }
        // A person with no usable photo is retried after a week (photos get added).
        if file.faces.isEmpty,
           let date = (try? facesURL(id).resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
           Date().timeIntervalSince(date) > 7 * 86400 { return nil }
        return file.faces
    }

    private func saveFaces(_ faces: [[Float]], for id: Int) {
        guard let data = try? JSONEncoder().encode(FaceFile(version: Self.referenceVersion, faces: faces)) else { return }
        try? data.write(to: facesURL(id), options: .atomic)
    }

    private func loadEngine() -> XRayFaceEngine? {
        if !engineLoaded {
            engineLoaded = true
            engine = XRayFaceEngine.bundled()
        }
        return engine
    }

    // MARK: Timelines

    /// One file per title and running time: another cut (an extended edition) of the
    /// same title gets its own timeline.
    private func timelineURL(_ key: String, duration: Double) -> URL {
        base.appendingPathComponent("titles/\(key)-\(Int((duration / 60).rounded())).json")
    }

    func loadTimeline(key: String, duration: Double) -> XRayTimeline? {
        // Neighbouring minutes too: two files of one cut can differ by a few seconds.
        let minutes = Int((duration / 60).rounded())
        for m in [minutes, minutes - 1, minutes + 1] {
            let url = base.appendingPathComponent("titles/\(key)-\(m).json")
            guard let data = try? Data(contentsOf: url),
                  let timeline = try? JSONDecoder().decode(XRayTimeline.self, from: data),
                  timeline.version == XRayTimeline.currentVersion,
                  abs(timeline.duration - duration) < 90 else { continue }
            return timeline
        }
        return nil
    }

    func save(_ timeline: XRayTimeline) {
        guard let data = try? JSONEncoder().encode(timeline) else { return }
        try? data.write(to: timelineURL(timeline.key, duration: timeline.duration), options: .atomic)
    }

    // MARK: Settings

    /// Saved titles and the space everything takes.
    func usage() -> (titles: Int, bytes: Int64) {
        let fm = FileManager.default
        var bytes: Int64 = 0, titles = 0
        for dir in ["titles", "faces"] {
            let url = base.appendingPathComponent(dir)
            for file in (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey])) ?? [] {
                bytes += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                if dir == "titles" { titles += 1 }
            }
        }
        return (titles, bytes)
    }

    func clearAll() {
        let fm = FileManager.default
        for dir in ["titles", "faces"] {
            let url = base.appendingPathComponent(dir)
            try? fm.removeItem(at: url)
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
