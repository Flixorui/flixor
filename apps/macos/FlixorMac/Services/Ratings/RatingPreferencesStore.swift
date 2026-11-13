//
//  RatingPreferencesStore.swift
//  FlixorMac
//
//  Per-profile choice of which ratings Details shows and where each comes
//  from. IMDb and Rotten Tomatoes keep their existing on/off keys, so earlier
//  choices carry over. Details and Settings → Details observe it.
//

import Combine
import SwiftUI

extension UserDefaults {
    private static func shownKey(_ kind: RatingKind) -> String {
        switch kind {
        case .imdb: return "showIMDbRating"
        case .rtCritics: return "showRottenTomatoesCritic"
        case .rtAudience: return "showRottenTomatoesAudience"
        default: return "ratingShown.\(kind.rawValue)"
        }
    }

    private static func sourceKey(_ kind: RatingKind) -> String { "ratingSource.\(kind.rawValue)" }

    func ratingShown(_ kind: RatingKind) -> Bool {
        object(forKey: profileKey(Self.shownKey(kind))) as? Bool ?? kind.defaultShown
    }

    func setRatingShown(_ kind: RatingKind, _ shown: Bool) {
        set(shown, forKey: profileKey(Self.shownKey(kind)))
    }

    func ratingSource(_ kind: RatingKind) -> RatingSource {
        guard let raw = string(forKey: profileKey(Self.sourceKey(kind))),
              let source = RatingSource(rawValue: raw),
              source == .automatic || kind.sources.contains(source) else { return .automatic }
        return source
    }

    func setRatingSource(_ kind: RatingKind, _ source: RatingSource) {
        set(source.rawValue, forKey: profileKey(Self.sourceKey(kind)))
    }
}

@MainActor
final class RatingPreferencesStore: ObservableObject {
    static let shared = RatingPreferencesStore()

    private let defaults = UserDefaults.standard
    private var profileObserver: AnyCancellable?

    @Published private(set) var shown: [RatingKind: Bool] = [:]
    @Published private(set) var sources: [RatingKind: RatingSource] = [:]

    private init() {
        load()
        // Profile switches call ProfileSettings.reloadFromStorage(), which
        // republishes every setting; follow it (same approach as DetailsSectionsStore).
        profileObserver = ProfileSettings.shared.objectWillChange
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.load() }
            }
    }

    func isShown(_ kind: RatingKind) -> Bool { shown[kind] ?? kind.defaultShown }

    func source(_ kind: RatingKind) -> RatingSource { sources[kind] ?? .automatic }

    func shownBinding(_ kind: RatingKind) -> Binding<Bool> {
        Binding(
            get: { self.isShown(kind) },
            set: { value in
                self.shown[kind] = value
                self.defaults.setRatingShown(kind, value)
                // ProfileSettings mirrors the three original toggles.
                switch kind {
                case .imdb: ProfileSettings.shared.showIMDbRating = value
                case .rtCritics: ProfileSettings.shared.showRottenTomatoesCritic = value
                case .rtAudience: ProfileSettings.shared.showRottenTomatoesAudience = value
                default: break
                }
            }
        )
    }

    func sourceBinding(_ kind: RatingKind) -> Binding<RatingSource> {
        Binding(
            get: { self.source(kind) },
            set: { value in
                self.sources[kind] = value
                self.defaults.setRatingSource(kind, value)
            }
        )
    }

    /// Ratings to draw for these inputs.
    func merged(_ inputs: RatingInputs) -> [MergedRating] {
        RatingsMerger.merge(inputs, shown: isShown, source: source)
    }

    private func load() {
        let newShown = Dictionary(uniqueKeysWithValues: RatingKind.allCases.map { ($0, defaults.ratingShown($0)) })
        let newSources = Dictionary(uniqueKeysWithValues: RatingKind.allCases.map { ($0, defaults.ratingSource($0)) })
        if newShown != shown { shown = newShown }
        if newSources != sources { sources = newSources }
    }
}
