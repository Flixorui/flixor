//
//  UpcomingViews.swift
//  FlixorMac
//
//  The Home "Upcoming" row and the Upcoming page: new episodes of the user's
//  shows that they haven't watched, and what airs next. Data comes from
//  UpcomingEpisodesStore.
//

import SwiftUI

/// Opens the Upcoming page.
struct UpcomingRoute: Hashable {}

/// Stable id of the Home "Upcoming" row.
let homeUpcomingRowId = "upcoming-episodes"

// MARK: - Home row

struct UpcomingHomeRow: View {
    let title: String
    let episodes: [UpcomingEpisode]
    let onOpen: (UpcomingEpisode) -> Void

    @EnvironmentObject private var router: NavigationRouter
    @EnvironmentObject private var mainViewState: MainViewState

    /// Same size as the Continue Watching cards above it.
    static let cardWidth: CGFloat = 380

    var body: some View {
        CarouselRow(
            title: title,
            items: Array(episodes.prefix(20)),
            itemWidth: Self.cardWidth,
            spacing: 16,
            rowHeight: Self.cardWidth * 0.5625 + 56,
            browseAction: { router.push(UpcomingRoute(), on: mainViewState.selectedTab) },
            browseLabel: String(localized: "See all")
        ) { episode in
            UpcomingEpisodeCard(episode: episode, width: Self.cardWidth) { onOpen(episode) }
        }
    }
}

struct UpcomingEpisodeCard: View {
    let episode: UpcomingEpisode
    let width: CGFloat
    let onTap: () -> Void

    @State private var isHovered = false
    @ObservedObject private var cardStyle = CardStyleStore.shared
    @Environment(\.flixorTheme) private var theme

    private var height: CGFloat { width * 0.5625 }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: DS.Space.s8) {
                ZStack(alignment: .topLeading) {
                    CachedAsyncImage(
                        url: episode.backdropURL.flatMap(URL.init(string:)),
                        maxPixelSize: ImageCache.fillPixelSize(width: width, height: height)
                    )
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipped()
                    .scaleEffect(isHovered ? 1.03 : 1)

                    LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)

                    UpcomingChip(text: UpcomingLabels.chip(for: episode), isAccent: episode.isNewUnwatched)
                        .padding(DS.Space.s10)
                }
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: cardStyle.cornerStyle.landscapeRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cardStyle.cornerStyle.landscapeRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(isHovered ? 0.35 : 0.08), lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(episode.showTitle)
                        .font(.flixor(.callout, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.flixor(.footnote))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
                .frame(width: width, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DS.Motion.standard) { isHovered = hovering }
        }
        .accessibilityLabel("\(episode.showTitle), \(UpcomingLabels.episodeLine(episode)), \(UpcomingLabels.chip(for: episode))")
    }

    private var subtitle: String {
        if episode.isNewUnwatched {
            return "\(UpcomingLabels.relativeDay(episode.airDate)) · \(UpcomingLabels.episodeLine(episode))"
        }
        return UpcomingLabels.episodeLine(episode)
    }
}

/// Date or "New" capsule over the artwork.
struct UpcomingChip: View {
    let text: String
    var isAccent = false

    @Environment(\.flixorTheme) private var theme

    var body: some View {
        Text(text)
            .font(.flixor(.caption, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, DS.Space.s8)
            .padding(.vertical, 3)
            .background {
                if isAccent {
                    Capsule().fill(theme.accent)
                } else {
                    Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                        .overlay(Capsule().fill(Color.black.opacity(0.35)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                }
            }
    }
}

// MARK: - New-episode settings

/// Settings rows for `UpcomingNewEpisodeRules` (Continue Watching settings).
struct UpcomingNewEpisodeSettings: View {
    @Binding var rules: UpcomingNewEpisodeRules

    var body: some View {
        SettingsGroupCard {
            SettingsRow(
                icon: "sparkles",
                iconColor: .red,
                title: "Show New Episodes",
                subtitle: "Episodes from the last 7 days you haven't watched, in the Upcoming row and page",
                showDivider: rules.showNew
            ) {
                Toggle("", isOn: $rules.showNew)
                    .labelsHidden()
                    .accessibilityLabel(Text("Show new episodes"))
            }
            if rules.showNew {
                SettingsRow(
                    icon: "play.circle.fill",
                    iconColor: .green,
                    title: "Only Shows You've Started",
                    subtitle: "Leave out shows you follow but haven't watched yet"
                ) {
                    Toggle("", isOn: $rules.onlyStartedShows)
                        .labelsHidden()
                        .accessibilityLabel(Text("Only shows you've started"))
                }
                SettingsRow(
                    icon: "gauge.with.dots.needle.67percent",
                    iconColor: .orange,
                    title: "How Far Behind",
                    subtitle: "Leave out shows with more unwatched episodes than this (needs Trakt)",
                    showDivider: false
                ) {
                    Picker("", selection: $rules.maxEpisodesBehind) {
                        ForEach(UpcomingNewEpisodeRules.behindChoices, id: \.self) { value in
                            Text(UpcomingNewEpisodeRules.behindLabel(value)).tag(value)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                    .accessibilityLabel(Text("Most unwatched episodes for a new episode card"))
                }
            }
        }
    }
}

// MARK: - Page

struct UpcomingEpisodesView: View {
    @ObservedObject private var store = UpcomingEpisodesStore.shared
    @EnvironmentObject private var router: NavigationRouter
    @EnvironmentObject private var mainViewState: MainViewState
    @Environment(\.flixorTheme) private var theme
    @Environment(\.windowMetrics) private var metrics

    enum Filter: String, CaseIterable, Identifiable {
        case all, outNow, thisWeek, premieres
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return String(localized: "All")
            case .outNow: return String(localized: "Out now")
            case .thisWeek: return String(localized: "This week")
            case .premieres: return String(localized: "Premieres")
            }
        }
    }

    @State private var filter: Filter = .all

    private struct DayGroup: Identifiable {
        let id: String
        let title: String
        let detail: String?
        let episodes: [UpcomingEpisode]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s24) {
                header
                hiddenNewNote
                content
            }
            .padding(.horizontal, metrics.pageGutter)
            .padding(.bottom, DS.Space.s48)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(BrowsePageBackdrop(url: store.episodes.first?.backdropURL.flatMap(URL.init(string:))))
        .navigationTitle("")
        .task { store.refreshIfStale() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s12) {
            Text("Upcoming")
                .font(.flixor(.largeTitle, weight: .bold))
                .foregroundStyle(theme.textPrimary)
            if case .loaded = store.state {
                Text(summary(store.episodes))
                    .font(.flixor(.callout))
                    .foregroundStyle(theme.textTertiary)
            }
            Spacer(minLength: DS.Space.s16)
            Picker("", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            newRulesMenu
        }
        .padding(.top, DS.Space.s8)
    }

    /// Same settings as Continue Watching settings, at hand on the page.
    private var newRulesMenu: some View {
        Menu {
            Toggle("Show New Episodes", isOn: $store.newRules.showNew)
            Toggle("Only Shows You've Started", isOn: $store.newRules.onlyStartedShows)
                .disabled(!store.newRules.showNew)
            Picker("How Far Behind", selection: $store.newRules.maxEpisodesBehind) {
                ForEach(UpcomingNewEpisodeRules.behindChoices, id: \.self) { value in
                    Text(UpcomingNewEpisodeRules.behindLabel(value)).tag(value)
                }
            }
            .disabled(!store.newRules.showNew)
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 18))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Which new episodes to show")
        .accessibilityLabel(Text("New episode settings"))
    }

    /// "2 new episodes hidden by your settings. Show all"
    @ViewBuilder
    private var hiddenNewNote: some View {
        let hidden = store.hiddenNewCount
        if hidden > 0, filter == .all || filter == .outNow {
            HStack(spacing: DS.Space.s8) {
                Image(systemName: "eye.slash")
                Text(hidden == 1
                     ? String(localized: "1 new episode is hidden by your settings.")
                     : String(localized: "\(hidden) new episodes are hidden by your settings."))
                Button("Show All") {
                    store.newRules.showNew = true
                    store.newRules.onlyStartedShows = false
                    store.newRules.maxEpisodesBehind = 0
                }
                .buttonStyle(.link)
            }
            .font(.flixor(.footnote))
            .foregroundStyle(theme.textSecondary)
            .padding(.leading, DS.Space.s10)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .idle, .loading:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 240)
        case .failed:
            message(String(localized: "Couldn't load your upcoming episodes."), retry: true)
        case .loaded:
            let list = store.episodes
            let groups = dayGroups(filtered(list))
            if groups.isEmpty {
                message(emptyText(hasAny: !list.isEmpty), retry: false)
            } else {
                VStack(alignment: .leading, spacing: DS.Space.s28) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: DS.Space.s6) {
                            HStack(spacing: DS.Space.s6) {
                                Text(group.title.uppercased())
                                    .font(.flixor(.footnote, weight: .semibold))
                                    .kerning(0.6)
                                    .foregroundStyle(theme.textSecondary)
                                if let detail = group.detail {
                                    Text("· \(detail)")
                                        .font(.flixor(.footnote))
                                        .foregroundStyle(theme.textTertiary)
                                }
                            }
                            .padding(.leading, DS.Space.s10)
                            ForEach(group.episodes) { episode in
                                UpcomingEpisodeRow(episode: episode) { open(episode) }
                            }
                        }
                    }
                }
            }
        }
    }

    private func message(_ text: String, retry: Bool) -> some View {
        VStack(spacing: DS.Space.s12) {
            Image(systemName: "calendar")
                .font(.system(size: 30))
                .foregroundStyle(theme.textTertiary)
            Text(text)
                .font(.flixor(.callout))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
            if retry {
                Button("Try Again") {
                    store.invalidate()
                    store.refreshIfStale()
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    private func emptyText(hasAny: Bool) -> String {
        if hasAny { return String(localized: "Nothing here for this filter.") }
        return String(localized: "No new or upcoming episodes for your shows in the next 30 days.")
    }

    private func summary(_ list: [UpcomingEpisode]) -> String {
        let fresh = list.filter(\.isNewUnwatched).count
        let coming = list.count - fresh
        var parts: [String] = []
        if fresh > 0 { parts.append(fresh == 1 ? String(localized: "1 new") : String(localized: "\(fresh) new")) }
        if coming > 0 {
            parts.append(coming == 1 ? String(localized: "1 coming up") : String(localized: "\(coming) coming up"))
        }
        return parts.joined(separator: " · ")
    }

    private func open(_ episode: UpcomingEpisode) {
        router.push(DetailsNavigationItem(item: episode.showItem), on: mainViewState.selectedTab)
    }

    private func filtered(_ list: [UpcomingEpisode]) -> [UpcomingEpisode] {
        let now = Date()
        switch filter {
        case .all: return list
        case .outNow: return list.filter(\.isNewUnwatched)
        case .thisWeek:
            let end = Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: now)) ?? now
            return list.filter { !$0.isNewUnwatched && $0.airDate < end }
        case .premieres: return list.filter { !$0.isNewUnwatched && $0.isPremiere }
        }
    }

    private func dayGroups(_ list: [UpcomingEpisode]) -> [DayGroup] {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: today) ?? today

        var groups: [DayGroup] = []
        let fresh = list.filter(\.isNewUnwatched)
        if !fresh.isEmpty {
            groups.append(DayGroup(id: "new", title: String(localized: "Out now"), detail: String(localized: "not watched yet"), episodes: fresh))
        }
        let coming = list.filter { !$0.isNewUnwatched }
        let todays = coming.filter { calendar.isDate($0.airDate, inSameDayAs: today) }
        if !todays.isEmpty {
            groups.append(DayGroup(id: "today", title: String(localized: "Today"), detail: UpcomingLabels.day(today), episodes: todays))
        }
        let tomorrows = coming.filter { calendar.isDate($0.airDate, inSameDayAs: tomorrow) }
        if !tomorrows.isEmpty {
            groups.append(DayGroup(id: "tomorrow", title: String(localized: "Tomorrow"), detail: UpcomingLabels.day(tomorrow), episodes: tomorrows))
        }
        let dayAfter = calendar.date(byAdding: .day, value: 1, to: tomorrow) ?? tomorrow
        let week = coming.filter { $0.airDate >= dayAfter && $0.airDate < weekEnd }
        if !week.isEmpty {
            groups.append(DayGroup(id: "week", title: String(localized: "This week"), detail: nil, episodes: week))
        }
        let later = coming.filter { $0.airDate >= weekEnd }
        if !later.isEmpty {
            groups.append(DayGroup(id: "later", title: String(localized: "Later"), detail: nil, episodes: later))
        }
        return groups
    }
}

private struct UpcomingEpisodeRow: View {
    let episode: UpcomingEpisode
    let onTap: () -> Void

    @State private var isHovered = false
    @Environment(\.flixorTheme) private var theme

    private static let artWidth: CGFloat = 168

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DS.Space.s16) {
                CachedAsyncImage(
                    url: episode.backdropURL.flatMap(URL.init(string:)),
                    maxPixelSize: ImageCache.fillPixelSize(width: Self.artWidth, height: Self.artWidth * 9 / 16)
                )
                .aspectRatio(contentMode: .fill)
                .frame(width: Self.artWidth, height: Self.artWidth * 9 / 16)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.thumbnail, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(episode.showTitle)
                        .font(.flixor(.headline, weight: .bold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    Text(UpcomingLabels.episodeLine(episode))
                        .font(.flixor(.callout))
                        .foregroundStyle(theme.textPrimary.opacity(0.85))
                        .lineLimit(1)
                    Text(meta)
                        .font(.flixor(.footnote))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: DS.Space.s12)

                VStack(alignment: .trailing, spacing: DS.Space.s8) {
                    if episode.isNewUnwatched {
                        UpcomingChip(text: String(localized: "New"), isAccent: true)
                    } else if episode.isPremiere {
                        UpcomingChip(text: String(localized: "Premiere"))
                    } else {
                        Text(trailingDate)
                            .font(.flixor(.callout, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                    }
                    if let fraction = episode.watchedFraction, (episode.episodesBehind ?? 0) <= 20 {
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.15))
                            Capsule().fill(theme.accent).frame(width: 120 * max(0, min(1, fraction)))
                        }
                        .frame(width: 120, height: 3)
                    }
                }
            }
            .padding(DS.Space.s10)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.r12, style: .continuous)
                    .fill(isHovered ? theme.hoverFill : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var trailingDate: String {
        let calendar = Calendar.current
        // Today and Tomorrow already head the group: show the time instead.
        if episode.hasTime && (calendar.isDateInToday(episode.airDate) || calendar.isDateInTomorrow(episode.airDate)) {
            return UpcomingLabels.time(episode.airDate)
        }
        return UpcomingLabels.relativeDay(episode.airDate)
    }

    private var meta: String {
        var parts: [String] = []
        if episode.isNewUnwatched {
            parts.append(String(localized: "Came out \(UpcomingLabels.relativeDay(episode.airDate))"))
        } else {
            var when = UpcomingLabels.relativeDay(episode.airDate)
            if episode.hasTime { when += " · \(UpcomingLabels.time(episode.airDate))" }
            parts.append(when)
        }
        if let runtime = episode.runtimeMinutes, runtime > 0 { parts.append(String(localized: "\(runtime) min")) }
        if let progress = UpcomingLabels.progress(episode) { parts.append(progress) }
        return parts.joined(separator: " · ")
    }
}
