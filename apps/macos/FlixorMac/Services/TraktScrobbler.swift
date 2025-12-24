//
//  TraktScrobbler.swift
//  FlixorMac
//
//  Manages Trakt scrobbling during playback
//  Automatically tracks what the user is watching and reports to Trakt
//

import Foundation
import FlixorKit

// MARK: - Scrobble Media Type

enum ScrobbleMediaType {
    case movie(TraktScrobbleMovie)
    case episode(show: TraktScrobbleShow, episode: TraktScrobbleEpisode)
}

// MARK: - Scrobble State

struct ScrobbleState {
    var isScrobbling: Bool = false
    var currentMedia: ScrobbleMediaType?
    var lastProgress: Double = 0
    var startTime: Date?
}

// MARK: - TraktScrobbler

@MainActor
class TraktScrobbler: ObservableObject {
    // MARK: - Singleton

    static let shared = TraktScrobbler()

    // MARK: - Published State

    @Published private(set) var isScrobbling = false
    @Published private(set) var currentTitle: String?

    // MARK: - Private State

    private var state = ScrobbleState()
    private let api = APIClient.shared

    // MARK: - Settings

    /// Check if scrobbling is enabled in settings
    private var isScrobblingEnabled: Bool {
        UserDefaults.standard.bool(forKey: "traktScrobbleEnabled")
    }

    // MARK: - Initialization

    private init() {
        // Set default value if not set
        if UserDefaults.standard.object(forKey: "traktScrobbleEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "traktScrobbleEnabled")
        }
    }

    // MARK: - Public API

    /// Start scrobbling for a media item
    /// - Parameters:
    ///   - item: The MediaItem being played
    ///   - initialProgress: Starting progress percentage (0-100)
    func startScrobble(for item: MediaItem, initialProgress: Double = 0) async {
        // Check if Trakt is authenticated and scrobbling is enabled
        guard FlixorCore.shared.isTraktAuthenticated else {
            print("⚠️ [Scrobbler] Trakt not authenticated, skipping scrobble")
            return
        }

        guard isScrobblingEnabled else {
            print("ℹ️ [Scrobbler] Scrobbling disabled in settings")
            return
        }

        // Stop any existing scrobble first
        if state.isScrobbling {
            await stopScrobble()
        }

        // Fetch external IDs from Plex metadata
        guard let ids = await fetchTraktIds(for: item) else {
            print("⚠️ [Scrobbler] Could not get Trakt IDs for: \(item.title)")
            return
        }

        // Build scrobble media based on type
        let mediaType = buildScrobbleMedia(for: item, ids: ids)

        // Start the scrobble
        do {
            let response: TraktScrobbleResponse
            switch mediaType {
            case .movie(let movie):
                response = try await FlixorCore.shared.trakt.scrobbleStart(movie: movie, progress: initialProgress)
                currentTitle = movie.title
            case .episode(let show, let episode):
                response = try await FlixorCore.shared.trakt.scrobbleStart(show: show, episode: episode, progress: initialProgress)
                currentTitle = "\(show.title ?? "Unknown") S\(episode.season)E\(episode.number)"
            }

            // Update state
            state = ScrobbleState(
                isScrobbling: true,
                currentMedia: mediaType,
                lastProgress: initialProgress,
                startTime: Date()
            )
            isScrobbling = true

            print("✅ [Scrobbler] Started scrobbling: \(currentTitle ?? "unknown") - Action: \(response.action)")
        } catch {
            print("❌ [Scrobbler] Failed to start scrobble: \(error)")
        }
    }

    /// Pause scrobbling (when user pauses playback)
    func pauseScrobble(progress: Double) async {
        guard state.isScrobbling, let media = state.currentMedia else {
            return
        }

        do {
            let response: TraktScrobbleResponse
            switch media {
            case .movie(let movie):
                response = try await FlixorCore.shared.trakt.scrobblePause(movie: movie, progress: progress)
            case .episode(let show, let episode):
                response = try await FlixorCore.shared.trakt.scrobblePause(show: show, episode: episode, progress: progress)
            }

            state.lastProgress = progress
            print("⏸️ [Scrobbler] Paused at \(Int(progress))% - Action: \(response.action)")
        } catch {
            print("❌ [Scrobbler] Failed to pause scrobble: \(error)")
        }
    }

    /// Resume scrobbling (when user resumes playback)
    func resumeScrobble(progress: Double) async {
        guard let media = state.currentMedia else {
            return
        }

        do {
            let response: TraktScrobbleResponse
            switch media {
            case .movie(let movie):
                response = try await FlixorCore.shared.trakt.scrobbleStart(movie: movie, progress: progress)
            case .episode(let show, let episode):
                response = try await FlixorCore.shared.trakt.scrobbleStart(show: show, episode: episode, progress: progress)
            }

            state.isScrobbling = true
            state.lastProgress = progress
            isScrobbling = true
            print("▶️ [Scrobbler] Resumed at \(Int(progress))% - Action: \(response.action)")
        } catch {
            print("❌ [Scrobbler] Failed to resume scrobble: \(error)")
        }
    }

    /// Stop scrobbling (when playback stops)
    /// If progress >= 80%, Trakt will mark the item as watched
    func stopScrobble(progress: Double? = nil) async {
        guard let media = state.currentMedia else {
            return
        }

        let finalProgress = progress ?? state.lastProgress

        do {
            let response: TraktScrobbleResponse
            switch media {
            case .movie(let movie):
                response = try await FlixorCore.shared.trakt.scrobbleStop(movie: movie, progress: finalProgress)
            case .episode(let show, let episode):
                response = try await FlixorCore.shared.trakt.scrobbleStop(show: show, episode: episode, progress: finalProgress)
            }

            // Check if it was marked as watched (action = "scrobble" means >80%)
            if response.action == "scrobble" {
                print("✅ [Scrobbler] Marked as WATCHED on Trakt! (Progress: \(Int(finalProgress))%)")
            } else {
                print("⏹️ [Scrobbler] Stopped at \(Int(finalProgress))% - Action: \(response.action)")
            }
        } catch {
            print("❌ [Scrobbler] Failed to stop scrobble: \(error)")
        }

        // Reset state
        state = ScrobbleState()
        isScrobbling = false
        currentTitle = nil
    }

    /// Update progress locally (no API call)
    func updateProgress(_ progress: Double) {
        if state.isScrobbling {
            state.lastProgress = progress
        }
    }

    /// Check if currently scrobbling
    func isCurrentlyScrobbling() -> Bool {
        return state.isScrobbling
    }

    // MARK: - Private Helpers

    /// Fetch TMDB/IMDB IDs from Plex metadata
    private func fetchTraktIds(for item: MediaItem) async -> TraktScrobbleIds? {
        // Try to get full metadata with GUIDs
        let ratingKey = item.id.replacingOccurrences(of: "plex:", with: "")

        do {
            // Fetch full metadata from Plex
            let fullItem: MediaItemFull = try await api.get("/api/plex/metadata/\(ratingKey)")

            var tmdbId: Int?
            var imdbId: String?
            var tvdbId: Int?

            // Parse GUIDs
            if let guids = fullItem.Guid {
                for guid in guids {
                    let id = guid.id
                    if id.hasPrefix("tmdb://") {
                        tmdbId = Int(id.replacingOccurrences(of: "tmdb://", with: ""))
                    } else if id.hasPrefix("imdb://") {
                        imdbId = id.replacingOccurrences(of: "imdb://", with: "")
                    } else if id.hasPrefix("tvdb://") {
                        tvdbId = Int(id.replacingOccurrences(of: "tvdb://", with: ""))
                    }
                }
            }

            // Also check the main guid field
            if let mainGuid = fullItem.guid {
                if mainGuid.hasPrefix("plex://movie/") || mainGuid.hasPrefix("plex://episode/") {
                    // Plex GUID format - need external IDs from Guid array
                } else if mainGuid.hasPrefix("com.plexapp.agents.imdb://") {
                    imdbId = mainGuid
                        .replacingOccurrences(of: "com.plexapp.agents.imdb://", with: "")
                        .components(separatedBy: "?").first
                } else if mainGuid.hasPrefix("com.plexapp.agents.themoviedb://") {
                    tmdbId = Int(mainGuid
                        .replacingOccurrences(of: "com.plexapp.agents.themoviedb://", with: "")
                        .components(separatedBy: "?").first ?? "")
                } else if mainGuid.hasPrefix("com.plexapp.agents.thetvdb://") {
                    tvdbId = Int(mainGuid
                        .replacingOccurrences(of: "com.plexapp.agents.thetvdb://", with: "")
                        .components(separatedBy: "/").first ?? "")
                }
            }

            // Need at least one valid ID
            if tmdbId != nil || imdbId != nil || tvdbId != nil {
                print("🔍 [Scrobbler] Found IDs - TMDB: \(tmdbId ?? 0), IMDB: \(imdbId ?? "nil"), TVDB: \(tvdbId ?? 0)")
                return TraktScrobbleIds(imdb: imdbId, tmdb: tmdbId, tvdb: tvdbId)
            }

            print("⚠️ [Scrobbler] No external IDs found in Plex metadata")
            return nil
        } catch {
            print("❌ [Scrobbler] Failed to fetch metadata: \(error)")
            return nil
        }
    }

    /// Build scrobble media from MediaItem
    private func buildScrobbleMedia(for item: MediaItem, ids: TraktScrobbleIds) -> ScrobbleMediaType {
        let itemType = item.type.lowercased()

        if itemType == "movie" {
            let movie = TraktScrobbleMovie(
                title: item.title,
                year: item.year,
                ids: ids
            )
            return .movie(movie)
        } else {
            // Episode - need show info and episode info
            let show = TraktScrobbleShow(
                title: item.grandparentTitle ?? item.title, // Show title
                year: nil, // Will be matched by IDs
                ids: ids
            )

            let episode = TraktScrobbleEpisode(
                season: item.parentIndex ?? 1,
                number: item.index ?? 1,
                title: item.title
            )

            return .episode(show: show, episode: episode)
        }
    }
}
