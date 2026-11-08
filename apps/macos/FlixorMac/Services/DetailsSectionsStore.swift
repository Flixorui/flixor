//
//  DetailsSectionsStore.swift
//  FlixorMac
//
//  Observable owner of the per-profile details-screen section settings
//  (UserDefaults+DetailsSections.swift). The details screen and its settings
//  page both observe it.
//

import Combine
import SwiftUI

@MainActor
final class DetailsSectionsStore: ObservableObject {
    static let shared = DetailsSectionsStore()

    private let defaults = UserDefaults.standard
    private var profileObserver: AnyCancellable?
    private var isLoading = false

    @Published var sections: [DetailsSectionPreference] {
        didSet {
            guard !isLoading, sections != oldValue else { return }
            defaults.detailsSectionPreferences = sections
        }
    }

    @Published var hideEpisodeSpoilers: Bool {
        didSet {
            guard !isLoading, hideEpisodeSpoilers != oldValue else { return }
            defaults.detailsHideEpisodeSpoilers = hideEpisodeSpoilers
        }
    }

    @Published var seasonPickerStyle: DetailsSeasonPickerStyle {
        didSet {
            guard !isLoading, seasonPickerStyle != oldValue else { return }
            defaults.detailsSeasonPickerStyle = seasonPickerStyle
        }
    }

    @Published var showEpisodeRatings: Bool {
        didSet {
            guard !isLoading, showEpisodeRatings != oldValue else { return }
            defaults.detailsShowEpisodeRatings = showEpisodeRatings
        }
    }

    private init() {
        sections = defaults.detailsSectionPreferences
        hideEpisodeSpoilers = defaults.detailsHideEpisodeSpoilers
        seasonPickerStyle = defaults.detailsSeasonPickerStyle
        showEpisodeRatings = defaults.detailsShowEpisodeRatings

        // Profile switches call ProfileSettings.reloadFromStorage(), which
        // republishes every setting; follow it (same approach as AppearanceStore).
        profileObserver = ProfileSettings.shared.objectWillChange
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.reload()
                }
            }
    }

    // MARK: - Queries

    /// Enabled section keys in the user's order.
    var orderedEnabledKeys: [DetailsSectionKey] {
        sections.filter(\.enabled).map(\.key)
    }

    func isEnabled(_ key: DetailsSectionKey) -> Bool {
        sections.first(where: { $0.key == key })?.enabled ?? true
    }

    // MARK: - Editing

    func setEnabled(_ key: DetailsSectionKey, _ enabled: Bool) {
        guard let index = sections.firstIndex(where: { $0.key == key }) else { return }
        sections[index].enabled = enabled
    }

    /// Moves `key` to the position currently held by `target`.
    func move(_ key: DetailsSectionKey, to target: DetailsSectionKey) {
        guard key != target,
              let from = sections.firstIndex(where: { $0.key == key }),
              let to = sections.firstIndex(where: { $0.key == target }) else { return }
        var updated = sections
        let item = updated.remove(at: from)
        updated.insert(item, at: to)
        sections = updated
    }

    /// Moves `key` one step up (negative) or down (positive).
    func move(_ key: DetailsSectionKey, by offset: Int) {
        guard let from = sections.firstIndex(where: { $0.key == key }) else { return }
        let to = from + offset
        guard sections.indices.contains(to) else { return }
        var updated = sections
        updated.swapAt(from, to)
        sections = updated
    }

    /// Restores the default order, visibility and episode display options.
    func resetToDefaults() {
        defaults.resetDetailsSectionSettings()
        reload()
    }

    /// Re-reads the settings for the current profile.
    func reload() {
        let newSections = defaults.detailsSectionPreferences
        let newSpoilers = defaults.detailsHideEpisodeSpoilers
        let newPickerStyle = defaults.detailsSeasonPickerStyle
        let newRatings = defaults.detailsShowEpisodeRatings
        isLoading = true
        if newSections != sections { sections = newSections }
        if newSpoilers != hideEpisodeSpoilers { hideEpisodeSpoilers = newSpoilers }
        if newPickerStyle != seasonPickerStyle { seasonPickerStyle = newPickerStyle }
        if newRatings != showEpisodeRatings { showEpisodeRatings = newRatings }
        isLoading = false
    }
}
