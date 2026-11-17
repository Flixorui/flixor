//
//  StremioSourcesView.swift
//  FlixorMac
//
//  Dedicated source browser for Stremio streams on macOS.
//

import SwiftUI

struct StremioSourcesView: View {
    @EnvironmentObject private var router: NavigationRouter
    @EnvironmentObject private var mainViewState: MainViewState
    @Environment(\.flixorTheme) private var theme
    @StateObject private var viewModel: StremioSourcesViewModel
    @State private var qualityFilter: String?
    @State private var sort: SourceSort = .best
    @State private var cache = EntryCache()
    /// Categories shown as a header only. Pre-release starts that way.
    @State private var collapsedCategories: Set<StremioReleaseCategory> = [.preRelease]
    /// Categories showing every row rather than the first few.
    @State private var expandedCategories: Set<StremioReleaseCategory> = []
    @State private var showHiddenTitles = false

    /// Rows per category before "Show all".
    private static let rowsPerCategory = 3

    enum SourceSort: CaseIterable, Identifiable {
        case best, size, addonOrder
        var id: Self { self }
        var label: String {
            switch self {
            case .best: return String(localized: "Best match")
            case .size: return String(localized: "Size")
            case .addonOrder: return String(localized: "Addon order")
            }
        }
    }

    init(destination: StremioSourcesDestination) {
        _viewModel = StateObject(wrappedValue: StremioSourcesViewModel(destination: destination))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s24) {
                heroSection

                if let notice = viewModel.destination.autoSelectNotice {
                    autoSelectNoticeBanner(notice)
                }

                // Sources show as each addon answers; the spinner stays only until the first playable one.
                let waitingForFirst = viewModel.isLoading && !viewModel.hasPlayableResults

                if !waitingForFirst, case .none = viewModel.emptyState {
                    filterBar
                }

                if let cached = viewModel.cachedSource {
                    cachedResumeCard(cached)
                }

                if waitingForFirst {
                    ProgressView("Loading sources…")
                        .progressViewStyle(.circular)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, DS.Space.s40)
                } else if case .none = viewModel.emptyState {
                    if let recommended = recommendedEntry { recommendedCard(recommended) }
                    groupedList
                    if viewModel.isLoading {
                        HStack(spacing: DS.Space.s8) {
                            ProgressView().controlSize(.small)
                            Text("Loading more sources…")
                                .font(.flixor(.caption))
                                .foregroundStyle(.secondary)
                        }
                    }
                    addonErrors
                    unsupportedSections
                } else {
                    emptyStateView
                }
            }
            .padding(.horizontal, DS.Space.s28)
            .padding(.top, DS.Space.s28)
            .padding(.bottom, DS.Space.s48)
        }
        .background(Color.black)
        .navigationTitle("Sources")
        .task {
            await viewModel.loadIfNeeded()
        }
        .alert("Stremio", isPresented: Binding(get: { viewModel.alertMessage != nil }, set: { if !$0 { viewModel.alertMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            Text("Choose a Source")
                .font(.flixor(.largeTitle, weight: .bold))
                .foregroundStyle(.white)
            Text(subtitleLine)
                .font(.flixor(.body))
                .foregroundStyle(.secondary)
        }
    }

    /// "Modern Family · S8 E4 · Weathering Heights", or the movie title.
    private var subtitleLine: AttributedString {
        let d = viewModel.destination
        var title = AttributedString(d.title)
        title.foregroundColor = .white
        title.font = .flixor(.body, weight: .semibold)
        guard d.mediaType == .episode, let season = d.seasonNumber, let episode = d.episodeNumber else { return title }
        var rest = AttributedString(" · S\(season) E\(episode)" + (d.episodeTitle.map { " · \($0)" } ?? ""))
        rest.foregroundColor = .secondary
        return title + rest
    }

    private func autoSelectNoticeBanner(_ notice: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.controlGap) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(theme.warning)
                .accessibilityHidden(true)
            Text(notice)
                .flixorFont(.callout)
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(DS.Space.itemGap)
        .background(theme.warning.opacity(DS.Opacity.hover), in: RoundedRectangle(cornerRadius: DS.Radius.compactCard, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Entries

    /// One row: a stream, or the same file on several servers.
    struct SourceEntry: Identifiable {
        let streams: [StremioPlayableStream]
        let facts: StremioStreamFacts
        let addonOrderIndex: Int
        let rank: Int
        var id: String { streams[0].id + "|" + (streams[0].addonInstallationId ?? "") }
        var primary: StremioPlayableStream { streams[0] }
    }

    /// Remembers the derived entries so a body pass doesn't rank every stream again.
    /// Not observed: it only caches values computed from observed state.
    private final class EntryCache {
        struct AllKey: Equatable {
            let version: Int
            let providerFilter: String
        }
        struct VisibleKey: Equatable {
            let all: AllKey
            let quality: String?
            let sort: SourceSort
        }
        struct RecommendedKey: Equatable {
            let all: AllKey
            let rules: StreamSelectionRules?
        }

        var allKey: AllKey?
        var all: [SourceEntry] = []
        var visibleKey: VisibleKey?
        var visible: [SourceEntry] = []
        var recommendedKey: RecommendedKey?
        var recommended: SourceEntry?
    }

    private var allEntriesKey: EntryCache.AllKey {
        EntryCache.AllKey(version: viewModel.resultsVersion, providerFilter: viewModel.selectedProviderFilter)
    }

    /// Every playable stream, grouped and ranked, before the quality filter.
    private var allEntries: [SourceEntry] {
        let key = allEntriesKey
        if cache.allKey != key {
            cache.all = buildAllEntries()
            cache.allKey = key
        }
        return cache.all
    }

    private func buildAllEntries() -> [SourceEntry] {
        let addonResults = viewModel.playableGroups
        let ranked = StremioSourceRanking.rankedPlayable(in: viewModel.groupedResults)
        let rankIndex = Dictionary(ranked.enumerated().map { ($1.id + ($1.addonInstallationId ?? ""), $0) }, uniquingKeysWith: { a, _ in a })
        var entries: [SourceEntry] = []
        for (groupIndex, group) in addonResults.enumerated() {
            var byFile: [String: Int] = [:]
            for stream in group.streams {
                let facts = StremioStreamFacts(stream, addonName: group.addonName)
                let rank = rankIndex[stream.id + (stream.addonInstallationId ?? "")] ?? Int.max
                if let key = facts.fileKey, let existing = byFile[key] {
                    let old = entries[existing]
                    entries[existing] = SourceEntry(streams: old.streams + [stream], facts: old.facts,
                                                    addonOrderIndex: old.addonOrderIndex, rank: min(old.rank, rank))
                } else {
                    if let key = facts.fileKey { byFile[key] = entries.count }
                    entries.append(SourceEntry(streams: [stream], facts: facts, addonOrderIndex: groupIndex, rank: rank))
                }
            }
        }
        return entries
    }

    private var visibleEntries: [SourceEntry] {
        let key = EntryCache.VisibleKey(all: allEntriesKey, quality: qualityFilter, sort: sort)
        if cache.visibleKey != key {
            cache.visible = buildVisibleEntries()
            cache.visibleKey = key
        }
        return cache.visible
    }

    private func buildVisibleEntries() -> [SourceEntry] {
        var entries = allEntries
        if let qualityFilter { entries = entries.filter { $0.facts.resolutionGroup == qualityFilter } }
        switch sort {
        case .best: entries.sort { $0.rank < $1.rank }
        case .size: entries.sort { ($0.facts.sizeBytes ?? 0) > ($1.facts.sizeBytes ?? 0) }
        case .addonOrder: break
        }
        return entries
    }

    /// The source automatic Play would choose: your rules when you use them, else the best ranked.
    private var recommendedEntry: SourceEntry? {
        let defaults = UserDefaults.standard
        let rules = defaults.stremioPlayAction == .matchRules ? defaults.stremioStreamRules : nil
        let key = EntryCache.RecommendedKey(all: allEntriesKey, rules: rules)
        if cache.recommendedKey != key {
            cache.recommended = buildRecommendedEntry(rules: rules)
            cache.recommendedKey = key
        }
        return cache.recommended
    }

    private func buildRecommendedEntry(rules: StreamSelectionRules?) -> SourceEntry? {
        let picked = (try? StreamAutoSelector(rules: rules))?.pick(in: viewModel.groupedResults)
            ?? StremioSourceRanking.rankedPlayable(in: viewModel.groupedResults).first
        guard let picked else { return nil }
        return allEntries.first { entry in entry.streams.contains { $0.id == picked.id && $0.addonInstallationId == picked.addonInstallationId } }
    }

    private var usesRules: Bool { UserDefaults.standard.stremioPlayAction == .matchRules }

    // MARK: - Filters

    private var filterBar: some View {
        let entries = allEntries
        let qualities = ["4K", "1080p", "Lower"].compactMap { q -> (String, Int)? in
            let count = entries.filter { $0.facts.resolutionGroup == q }.count
            return count > 0 ? (q, count) : nil
        }
        return HStack(spacing: DS.Space.s8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s8) {
                    BrowseCountChip(title: String(localized: "All"), count: entries.count, selected: qualityFilter == nil) { qualityFilter = nil }
                    ForEach(qualities, id: \.0) { quality, count in
                        BrowseCountChip(title: quality == "Lower" ? String(localized: "720p & lower") : quality, count: count, selected: qualityFilter == quality) {
                            qualityFilter = qualityFilter == quality ? nil : quality
                        }
                    }
                    if viewModel.groupedResults.count > 1 {
                        Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 18).padding(.horizontal, DS.Space.s4)
                        BrowseCountChip(title: String(localized: "All addons"), selected: viewModel.selectedProviderFilter == "all") {
                            viewModel.selectedProviderFilter = "all"
                        }
                        ForEach(viewModel.groupedResults.filter { !$0.streams.isEmpty }) { result in
                            BrowseCountChip(title: result.addonName, count: result.streams.filter(\.playable).count,
                                            selected: viewModel.selectedProviderFilter == result.installationId) {
                                viewModel.selectedProviderFilter = viewModel.selectedProviderFilter == result.installationId ? "all" : result.installationId
                            }
                        }
                    }
                }
                .padding(.vertical, DS.Space.s2)
            }
            LibraryPillMenu(label: String(localized: "Sort"), value: sort.label, isActive: sort != .best) {
                ForEach(SourceSort.allCases) { option in
                    Button { sort = option } label: {
                        if sort == option { Label(option.label, systemImage: "checkmark") } else { Text(option.label) }
                    }
                }
            }
        }
    }

    // MARK: - Recommended and list

    private func recommendedCard(_ entry: SourceEntry) -> some View {
        HStack(spacing: DS.Space.s16) {
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                Text(usesRules ? "Recommended · matches your source rules" : "Recommended · best quality available")
                    .font(.flixor(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)
                StremioFactBadges(facts: entry.facts)
                Text([entry.facts.provider, entry.facts.filename].compactMap { $0 }.joined(separator: " · "))
                    .font(.flixor(.footnote))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: DS.Space.s12)
            Button { play(entry.primary) } label: {
                Label("Play", systemImage: "play.fill")
            }
            .buttonStyle(SettingsPrimaryButtonStyle())
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(DS.Space.s16)
        .background(
            LinearGradient(colors: [Color.white.opacity(0.09), Color.white.opacity(0.03)], startPoint: .leading, endPoint: .trailing),
            in: RoundedRectangle(cornerRadius: DS.Radius.r12, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.r12, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }

    /// Sources in sections by release type (Remux, BluRay Disc, WEB-DL, ...), each
    /// showing its best few, after a note about results left out for another title.
    private var groupedList: some View {
        let entries = visibleEntries
        let byCategory = Dictionary(grouping: entries, by: \.facts.category)
        let allByCategory = Dictionary(grouping: allEntries, by: \.facts.category)
        return VStack(alignment: .leading, spacing: DS.Space.s20) {
            hiddenTitlesNote
            if showHiddenTitles, !viewModel.hiddenStreams.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s10) {
                    Text("Different title or year")
                        .font(.flixor(.headline, weight: .bold))
                    rowsContainer(hiddenEntries)
                        .opacity(0.6)
                }
            }
            if entries.isEmpty {
                Text(allEntries.isEmpty
                     ? String(localized: "No source is for this title.")
                     : String(localized: "No sources at this quality."))
                    .font(.flixor(.callout))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, DS.Space.s12)
            }
            ForEach(StremioReleaseCategory.displayOrder) { category in
                if let rows = byCategory[category], !rows.isEmpty {
                    categorySection(category, rows: rows, all: allByCategory[category] ?? rows)
                }
            }
        }
    }

    private func categorySection(_ category: StremioReleaseCategory, rows: [SourceEntry], all: [SourceEntry]) -> some View {
        let collapsed = collapsedCategories.contains(category)
        let expanded = expandedCategories.contains(category)
        let shown = expanded ? rows : Array(rows.prefix(Self.rowsPerCategory))
        // Counts per resolution across the whole category, whatever the quality filter.
        let breakdown = [("4K", "4K"), ("1080p", "1080p"), ("Lower", String(localized: "720p & lower"))].compactMap { key, label -> String? in
            let count = all.filter { $0.facts.resolutionGroup == key }.count
            return count > 0 ? "\(label) \(count)" : nil
        }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: DS.Space.s10) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s8) {
                Text(category.label).font(.flixor(.headline, weight: .bold))
                Text("\(rows.count)").font(.flixor(.callout)).foregroundStyle(.secondary)
                Text(breakdown).font(.flixor(.caption)).foregroundStyle(.tertiary)
                Spacer(minLength: DS.Space.s8)
                Button(collapsed ? String(localized: "Expand") : String(localized: "Collapse")) {
                    if collapsed { collapsedCategories.remove(category) } else { collapsedCategories.insert(category) }
                }
                .buttonStyle(.plain)
                .font(.flixor(.caption, weight: .semibold))
                .foregroundStyle(.secondary)
            }
            if category == .preRelease {
                Label("Recorded in a cinema or from a screener. Picture and sound are poor.", systemImage: "exclamationmark.triangle.fill")
                    .font(.flixor(.caption))
                    .foregroundStyle(theme.warning)
            }
            if !collapsed {
                rowsContainer(shown, moreCount: expanded ? 0 : rows.count - shown.count) {
                    expandedCategories.insert(category)
                }
            }
        }
    }

    private func rowsContainer(_ rows: [SourceEntry], moreCount: Int = 0, showAll: @escaping () -> Void = {}) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, entry in
                StremioSourceRow(entry: entry, onPlay: play)
                if index < rows.count - 1 || moreCount > 0 {
                    Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                }
            }
            if moreCount > 0 {
                Button(action: showAll) {
                    Text("Show all \(rows.count + moreCount)")
                        .font(.flixor(.caption, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DS.Space.s14)
                        .padding(.vertical, DS.Space.s10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: DS.Radius.r12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.r12, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }

    /// "2 hidden · for a different title or year", with Show / Hide.
    @ViewBuilder
    private var hiddenTitlesNote: some View {
        let count = viewModel.hiddenStreams.count
        if count > 0 {
            HStack(spacing: DS.Space.s10) {
                Image(systemName: "eye.slash")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("\(count) hidden · for a different title or year")
                    .font(.flixor(.callout))
                    .foregroundStyle(theme.textPrimary)
                Spacer(minLength: DS.Space.s8)
                Button(showHiddenTitles ? String(localized: "Hide") : String(localized: "Show")) {
                    showHiddenTitles.toggle()
                }
                .buttonStyle(.plain)
                .font(.flixor(.caption, weight: .semibold))
                .padding(.horizontal, DS.Space.s10)
                .padding(.vertical, 3)
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            }
            .padding(.horizontal, DS.Space.s12)
            .padding(.vertical, DS.Space.s8)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: DS.Radius.compactCard, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.compactCard, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
        }
    }

    private var hiddenEntries: [SourceEntry] {
        viewModel.hiddenStreams.map { stream in
            SourceEntry(streams: [stream], facts: StremioStreamFacts(stream, addonName: stream.addonName ?? "Stremio"),
                        addonOrderIndex: Int.max, rank: Int.max)
        }
    }

    /// Addons that failed, as one quiet line each.
    @ViewBuilder
    private var addonErrors: some View {
        let failed = viewModel.groupedResults.filter { $0.streams.isEmpty && $0.error != nil }
        if !failed.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                ForEach(failed) { result in
                    Label("\(result.addonName): \(result.error ?? "")", systemImage: "exclamationmark.triangle")
                        .font(.flixor(.caption))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func play(_ stream: StremioPlayableStream) {
        Task {
            // Same subtitle-addon wait as automatic Play; the player asks again once playback starts.
            let deadline = Date().addingTimeInterval(TimeInterval(UserDefaults.standard.stremioAutoPickTimeLimit))
            if let destination = await viewModel.select(stream: stream, subtitleDeadline: deadline) {
                appendToCurrentTabPath(destination)
            }
        }
    }

    private var unsupportedSections: some View {
        Group {
            let groups = viewModel.unsupportedGroups
            if !groups.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s18) {
                    sectionHeader(title: String(localized: "Alternate Platforms"), subtitle: String(localized: "Returned by addons but not currently playable in-app"))
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: DS.Space.s12) {
                            Text(group.addonName)
                                .font(.flixor(.body, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                            VStack(spacing: DS.Space.s12) {
                                ForEach(group.streams) { stream in
                                    StremioStreamRow(stream: stream, addonName: group.addonName) {}
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(alignment: .leading, spacing: DS.Space.s10) {
            Text(viewModel.emptyState.title)
                .font(.flixor(.title3, weight: .semibold))
                .foregroundStyle(.white)
            Text(viewModel.emptyState.message)
                .font(.flixor(.callout))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Space.s18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: DS.Radius.r16, style: .continuous))
    }

    private func cachedResumeCard(_ cached: CachedPlaybackSource) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s10) {
            HStack {
                VStack(alignment: .leading, spacing: DS.Space.s4) {
                    Text("Resume Cached Source")
                        .font(.flixor(.bodyLarge, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(cached.playbackItem.streamLabel ?? cached.playbackItem.addonName ?? String(localized: "Previously selected source"))
                        .font(.flixor(.footnote))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Resume") {
                    Task {
                        if let destination = await viewModel.resumeCachedPlayback() {
                            appendToCurrentTabPath(destination)
                        }
                    }
                }
                .buttonStyle(SettingsPrimaryButtonStyle())
            }

            Text("Cached until \(cached.expiresAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.flixor(.caption))
                .foregroundStyle(.secondary)
        }
        .padding(DS.Space.s16)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: DS.Radius.r12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.r12, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func sectionHeader(title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            Text(title)
                .font(.flixor(.headline, weight: .bold))
                .foregroundStyle(.white)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.flixor(.caption))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func appendToCurrentTabPath(_ destination: PlayerDestination) {
        switch mainViewState.selectedTab {
        case .home:
            router.homePath.append(destination)
        case .search:
            router.searchPath.append(destination)
        case .library:
            router.libraryPath.append(destination)
        case .myList:
            router.myListPath.append(destination)
        case .newPopular:
            router.newPopularPath.append(destination)
        case .downloads:
            router.downloadsPath.append(destination)
        }
    }
}

// MARK: - Row and badges

/// Badges on the left, provider and file name beside them, Play on hover.
private struct StremioSourceRow: View {
    let entry: StremioSourcesView.SourceEntry
    let onPlay: (StremioPlayableStream) -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: DS.Space.s12) {
            StremioFactBadges(facts: entry.facts, fitting: true)
                .frame(width: 380, alignment: .leading)
                .clipped()
            VStack(alignment: .leading, spacing: 1) {
                // A grouped row stands for every server, so drop "· Server 1".
                Text(entry.streams.count > 1
                     ? entry.facts.provider.replacingOccurrences(of: " · Server [0-9]+$", with: "", options: .regularExpression)
                     : entry.facts.provider)
                    .font(.flixor(.callout, weight: .semibold))
                    .lineLimit(1)
                if let filename = entry.facts.filename {
                    Text(filename)
                        .font(.flixor(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: DS.Space.s8)
            if entry.streams.count > 1 {
                Menu {
                    ForEach(Array(entry.streams.enumerated()), id: \.offset) { index, stream in
                        Button(String(localized: "Server \(index + 1)")) { onPlay(stream) }
                    }
                } label: {
                    Text("\(entry.streams.count) servers")
                        .font(.flixor(.caption, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, DS.Space.s8)
                        .padding(.vertical, 3)
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("The same file on \(entry.streams.count) servers. Click the row to use the first.")
            }
            Image(systemName: "play.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.white))
                .opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, DS.Space.s14)
        .padding(.vertical, DS.Space.s10)
        .background(hovering ? Color.white.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onPlay(entry.primary) }
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onPlay(entry.primary) }
    }
}

struct StremioFactBadges: View {
    let facts: StremioStreamFacts
    /// In a fixed-width column: drop the least useful badges rather than overflow.
    var fitting = false

    var body: some View {
        if fitting {
            ViewThatFits(in: .horizontal) {
                badges(languageLimit: 3, showCached: true)
                badges(languageLimit: 2, showCached: true)
                badges(languageLimit: 2, showCached: false)
                badges(languageLimit: 0, showCached: false)
            }
        } else {
            badges(languageLimit: 3, showCached: true)
        }
    }

    private func badges(languageLimit: Int, showCached: Bool) -> some View {
        HStack(spacing: DS.Space.s4) {
            if let resolution = facts.resolution { badge(resolution, style: .resolution) }
            if let hdr = facts.hdr { badge(hdr, style: hdr.hasPrefix("DV") ? .dolbyVision : .hdr) }
            if let codec = facts.codec { badge(codec) }
            if let audio = facts.audio { badge(audio) }
            if let size = facts.sizeText { badge(size) }
            if languageLimit > 0, !facts.languages.isEmpty {
                let shown = facts.languages.prefix(languageLimit).joined(separator: " · ")
                let extra = facts.languages.count - min(languageLimit, facts.languages.count)
                badge(extra > 0 ? "\(shown) +\(extra)" : shown)
            }
            if showCached, facts.cached { badge(String(localized: "Cached"), style: .cached) }
        }
        .lineLimit(1)
        .fixedSize()
    }

    enum Style { case plain, resolution, hdr, dolbyVision, cached }

    private func badge(_ text: String, style: Style = .plain) -> some View {
        let colors: (Color, Color) = {
            switch style {
            case .plain: return (Color.white.opacity(0.1), Color.white.opacity(0.9))
            case .resolution: return (.white, .black)
            case .hdr: return (Color.yellow.opacity(0.18), Color(red: 0.99, green: 0.9, blue: 0.54))
            case .dolbyVision: return (Color.purple.opacity(0.24), Color(red: 0.91, green: 0.84, blue: 1))
            case .cached: return (Color.green.opacity(0.16), Color(red: 0.6, green: 0.92, blue: 0.68))
            }
        }()
        return Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(colors.1)
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(colors.0, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .fixedSize()
    }
}
