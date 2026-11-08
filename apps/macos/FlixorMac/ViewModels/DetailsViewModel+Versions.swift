//
//  DetailsViewModel+Versions.swift
//  FlixorMac
//
//  Technical badges, edition title, media versions
//

import Foundation
import SwiftUI
import FlixorKit

extension DetailsViewModel {
    func addBadge(_ badge: String) {
        guard !badge.isEmpty else { return }
        if !badges.contains(badge) {
            badges.append(badge)
        }
    }

    private func addBadges(_ list: [String]) {
        for badge in list where !badge.isEmpty {
            addBadge(badge)
        }
    }

    func appendTechnicalBadges(from media: [PlexMedia]) {
        guard let first = media.first else { return }
        var extra: [String] = []
        let width = first.width ?? 0
        let height = first.height ?? 0
        if width >= 3800 || height >= 2100 {
            extra.append("4K")
        }

        // Check videoProfile for HDR info
        let profile = (first.videoProfile ?? "").lowercased()
        var hasHDR = false
        var hasDV = false

        // Dolby Vision detection
        if profile.contains("dv") || profile.contains("dolby vision") || profile.contains("dovi") {
            hasDV = true
        }
        // HDR detection - include "main 10" which indicates HDR capability
        if profile.contains("hdr") || profile.contains("hlg") || profile.contains("pq") ||
           profile.contains("smpte2084") || profile.contains("main 10") || profile.contains("main10") {
            hasHDR = true
        }

        // Also check video stream's displayTitle (streamType == 1) which often has HDR info
        if let part = first.Part?.first, let streams = part.Stream {
            for stream in streams where stream.streamType == 1 {
                let displayTitle = (stream.displayTitle ?? "").lowercased()
                if displayTitle.contains("dolby vision") || displayTitle.contains("dovi") || displayTitle.contains(" dv") {
                    hasDV = true
                }
                if displayTitle.contains("hdr") || displayTitle.contains("hlg") {
                    hasHDR = true
                }
            }
        }

        // Add badges - DV implies HDR so only add one
        if hasDV {
            extra.append("Dolby Vision")
        } else if hasHDR {
            extra.append("HDR")
        }

        let audioProfile = (first.audioProfile ?? "").lowercased()
        let audioCodec = (first.audioCodec ?? "").lowercased()
        if audioProfile.contains("atmos") || audioCodec.contains("atmos") || audioCodec.contains("truehd") {
            extra.append("Atmos")
        }
        addBadges(extra)
    }

    func extractEditionTitle(from media: [PlexMedia]) {
        guard let first = media.first else { return }
        // Priority 1: Use explicit editionTitle from API
        if let edition = first.editionTitle, !edition.isEmpty {
            self.editionTitle = edition
            return
        }
        // Priority 2: Parse from filename {edition-XXX} pattern
        if let filePath = first.Part?.first?.file {
            if let match = filePath.range(of: #"\{edition-([^}]+)\}"#, options: .regularExpression) {
                let fullMatch = String(filePath[match])
                // Extract the edition name between {edition- and }
                let start = fullMatch.index(fullMatch.startIndex, offsetBy: 9) // "{edition-".count
                let end = fullMatch.index(fullMatch.endIndex, offsetBy: -1) // remove "}"
                self.editionTitle = String(fullMatch[start..<end])
                return
            }
        }
        self.editionTitle = nil
    }

    func hydrateVersions(from media: [PlexMedia]) {
        print("🎞️ [hydrateVersions] Processing \(media.count) media item(s)")
        var vds: [VersionDetail] = []
        for (idx, mm) in media.enumerated() {
            let id = mm.id ?? String(idx)
            let width = mm.width ?? 0
            let height = mm.height ?? 0
            let resoLabel: String? = {
                if width >= 3800 || height >= 2100 { return "4K" }
                if width >= 1900 || height >= 1000 { return "1080p" }
                if width >= 1260 || height >= 700 { return "720p" }
                if width > 0 && height > 0 { return "\(width)x\(height)" }
                return nil
            }()
            let vcodec = (mm.videoCodec ?? "").uppercased()
            let ach = mm.audioChannels.map { "\($0)CH" } ?? ""
            let labelParts = [resoLabel, vcodec.isEmpty ? nil : vcodec, ach.isEmpty ? nil : ach].compactMap { $0 }
            let part = mm.Part?.first
            let streams = part?.Stream ?? []
            let audio = streams.enumerated().filter { $0.element.streamType == 2 }.map { offset, stream -> Track in
                let name = stream.displayTitle ?? stream.languageTag ?? stream.language ?? String(localized: "Audio \(offset + 1)")
                return Track(id: stream.id ?? String(offset), name: name, language: stream.languageTag ?? stream.language)
            }
            let subs = streams.enumerated().filter { $0.element.streamType == 3 }.map { offset, stream -> Track in
                let name = stream.displayTitle ?? stream.languageTag ?? stream.language ?? String(localized: "Sub \(offset + 1)")
                return Track(id: stream.id ?? String(offset), name: name, language: stream.languageTag ?? stream.language)
            }
            // Get video stream displayTitle (streamType == 1) for HDR detection
            let videoDisplayTitle = streams.first { $0.streamType == 1 }?.displayTitle
            let sizeMB = part?.size.map { Double($0) / (1024.0 * 1024.0) }
            let tech = VersionDetail.TechnicalInfo(
                resolution: (width > 0 && height > 0) ? "\(width)x\(height)" : nil,
                videoCodec: mm.videoCodec,
                videoProfile: mm.videoProfile,
                videoDisplayTitle: videoDisplayTitle,
                audioCodec: mm.audioCodec,
                audioChannels: mm.audioChannels,
                bitrate: mm.bitrate,
                fileSizeMB: sizeMB,
                durationMin: mm.duration.map { Int($0 / 60000) },
                subtitleCount: subs.count,
                container: mm.container
            )
            let label = labelParts.isEmpty ? String(localized: "Version \(idx + 1)") : labelParts.joined(separator: " ")
            vds.append(VersionDetail(id: id, label: label, technical: tech, audioTracks: audio, subtitleTracks: subs))
        }
        if !vds.isEmpty {
            versions = vds
            if activeVersionId == nil {
                activeVersionId = vds.first?.id
            }
            audioTracks = vds.first?.audioTracks ?? []
            subtitleTracks = vds.first?.subtitleTracks ?? []

            // Add CC badge if there are any subtitles
            if !subtitleTracks.isEmpty {
                addBadges(["CC"])
            }

            // Add SDH badge if any subtitle contains "SDH" in its name
            if subtitleTracks.contains(where: { $0.name.uppercased().contains("SDH") }) {
                addBadges(["SDH"])
            }

            print("✅ [hydrateVersions] Successfully populated \(vds.count) version(s): \(vds.map { $0.label }.joined(separator: ", "))")
            print("   Active version: \(activeVersionId ?? "nil"), \(audioTracks.count) audio track(s), \(subtitleTracks.count) subtitle(s)")
        } else {
            print("⚠️ [hydrateVersions] No versions created from media array")
        }
    }

    /// Fetch versions for a specific item (episode/movie) by ratingKey
    /// Returns versions array for that item, or empty if only one version
    func fetchVersionsForItem(ratingKey: String) async -> [VersionDetail] {
        let cleanKey = ratingKey.replacingOccurrences(of: "plex:", with: "")
        do {
            let meta: PlexMeta = try await api.get("/api/plex/metadata/\(cleanKey)")
            guard let media = meta.Media, media.count > 1 else {
                print("📺 [fetchVersionsForItem] Item \(cleanKey) has \(meta.Media?.count ?? 0) version(s), no picker needed")
                return []
            }
            // Build version details
            var vds: [VersionDetail] = []
            for (idx, mm) in media.enumerated() {
                let id = mm.id ?? String(idx)
                let width = mm.width ?? 0
                let height = mm.height ?? 0
                let resoLabel: String? = {
                    if width >= 3800 || height >= 2100 { return "4K" }
                    if width >= 1900 || height >= 1000 { return "1080p" }
                    if width >= 1260 || height >= 700 { return "720p" }
                    if width > 0 && height > 0 { return "\(width)x\(height)" }
                    return nil
                }()
                let vcodec = (mm.videoCodec ?? "").uppercased()
                let ach = mm.audioChannels.map { "\($0)CH" } ?? ""
                let labelParts = [resoLabel, vcodec.isEmpty ? nil : vcodec, ach.isEmpty ? nil : ach].compactMap { $0 }
                let part = mm.Part?.first
                let streams = part?.Stream ?? []
                let audio = streams.enumerated().filter { $0.element.streamType == 2 }.map { offset, stream -> Track in
                    let name = stream.displayTitle ?? stream.languageTag ?? stream.language ?? String(localized: "Audio \(offset + 1)")
                    return Track(id: stream.id ?? String(offset), name: name, language: stream.languageTag ?? stream.language)
                }
                let subs = streams.enumerated().filter { $0.element.streamType == 3 }.map { offset, stream -> Track in
                    let name = stream.displayTitle ?? stream.languageTag ?? stream.language ?? String(localized: "Sub \(offset + 1)")
                    return Track(id: stream.id ?? String(offset), name: name, language: stream.languageTag ?? stream.language)
                }
                let videoDisplayTitle = streams.first { $0.streamType == 1 }?.displayTitle
                let sizeMB = part?.size.map { Double($0) / (1024.0 * 1024.0) }
                let tech = VersionDetail.TechnicalInfo(
                    resolution: (width > 0 && height > 0) ? "\(width)x\(height)" : nil,
                    videoCodec: mm.videoCodec,
                    videoProfile: mm.videoProfile,
                    videoDisplayTitle: videoDisplayTitle,
                    audioCodec: mm.audioCodec,
                    audioChannels: mm.audioChannels,
                    bitrate: mm.bitrate,
                    fileSizeMB: sizeMB,
                    durationMin: mm.duration.map { $0 / 60000 },
                    subtitleCount: subs.count,
                    container: mm.container
                )
                vds.append(VersionDetail(id: id, label: labelParts.joined(separator: " "), technical: tech, audioTracks: audio, subtitleTracks: subs))
            }
            print("📺 [fetchVersionsForItem] Found \(vds.count) versions for item \(cleanKey)")
            return vds
        } catch {
            print("⚠️ [fetchVersionsForItem] Error fetching versions: \(error)")
            return []
        }
    }
}
