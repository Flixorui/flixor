//
//  PlayerMarker+SkipSegments.swift
//  FlixorMac
//
//  Bridges community skip segments into the player's PlayerMarker pipeline and
//  gives the UI what it needs to label skip buttons and draw seek-bar ticks.
//

import Foundation

extension PlayerMarker {
    static let communityIdPrefix = "community-"

    /// Normalized segment type (intro, recap, credits, preview, postcredits), nil for other Plex types.
    var segmentType: SkipSegmentType? { SkipSegmentType(markerType: type) }

    /// True when the marker came from IntroDB / AniSkip / Anime-Skip rather than Plex.
    var isCommunitySegment: Bool { id.hasPrefix(Self.communityIdPrefix) }

    /// Provider that supplied this marker.
    var provider: SkipSegmentProvider {
        guard isCommunitySegment else { return .plex }
        let rest = id.dropFirst(Self.communityIdPrefix.count)
        return SkipSegmentProvider(rawValue: String(rest.prefix { $0 != "-" })) ?? .plex
    }

    /// Whether the skip button / auto-skip applies to this marker.
    var isSkippable: Bool { segmentType?.isSkippable ?? false }

    /// Label for the skip button: "Skip Intro", "Skip Recap", "Skip Credits", "Skip Preview".
    var skipButtonTitle: String {
        "Skip \(segmentType?.displayName ?? type.capitalized)"
    }

    /// Builds a marker from a community segment. Open-ended segments need the
    /// file duration; without it they are dropped (rebuilt once duration is known).
    init?(segment: SkipSegment, durationSeconds: TimeInterval) {
        let endSeconds: TimeInterval
        if let end = segment.end {
            endSeconds = durationSeconds > 0 ? min(end, durationSeconds) : end
        } else if durationSeconds > 0 {
            endSeconds = durationSeconds
        } else {
            return nil
        }
        let startMs = Int((segment.start * 1000).rounded())
        let endMs = Int((endSeconds * 1000).rounded())
        guard endMs > startMs else { return nil }
        self.init(
            id: "\(Self.communityIdPrefix)\(segment.provider.rawValue)-\(segment.type.rawValue)-\(startMs)",
            type: segment.type.markerType,
            startTimeOffset: startMs,
            endTimeOffset: endMs
        )
    }
}
