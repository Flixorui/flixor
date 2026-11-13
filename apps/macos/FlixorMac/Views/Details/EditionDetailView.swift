//
//  EditionDetailView.swift
//  FlixorMac
//
//  Full page for one Blu-ray or 4K edition (EditionRoute), opened from
//  Physical Releases on Details and from Library → Physical. Built like the
//  person page: wide windows show the cover, facts, collection button and
//  links as a sidebar with the content scrolling beside it; narrow windows
//  stack them above. Content blocks follow Settings → MyBluray → Edition Page.
//

import SwiftUI

/// Navigation value for the edition page.
struct EditionRoute: Hashable {
    let summary: MBEditionSummary
    /// From Library → Physical: look the film up in Plex and offer to open it.
    var offersLibraryLink = false
}

struct EditionPage: View {
    let route: EditionRoute

    @EnvironmentObject private var router: NavigationRouter
    @EnvironmentObject private var mainViewState: MainViewState
    @Environment(\.flixorTheme) private var theme
    @Environment(\.windowMetrics) private var metrics
    @ObservedObject private var settings = MyBluraySettingsStore.shared
    @ObservedObject private var collection = PhysicalCollectionStore.shared

    @State private var edition: MBEdition?
    @State private var failed = false
    @State private var plexMatch: MediaItem?
    @State private var contentWidth: CGFloat = 0

    private static let sidebarMinContentWidth: CGFloat = 1080

    private var summary: MBEditionSummary { route.summary }
    private var availableWidth: CGFloat { contentWidth > 0 ? contentWidth : metrics.width }
    private var usesSidebar: Bool { availableWidth >= Self.sidebarMinContentWidth }
    private var gutter: CGFloat { metrics.pageGutter }
    private var sidebarWidth: CGFloat { (300 * metrics.itemScale).rounded() }

    var body: some View {
        Group {
            if usesSidebar { wideLayout } else { stackedLayout }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .readContentWidth(into: $contentWidth)
        .background(BrowsePageBackdrop(url: backdropURL))
        .navigationTitle("")
        .task(id: summary.id) { await load() }
    }

    private var backdropURL: URL? {
        if let shot = edition?.screenshots.first { return URL(string: shot.url) }
        return summary.coverImage.flatMap(URL.init(string:))
    }

    private func load() async {
        failed = false
        async let details: MBEdition? = try? await MyBlurayService.shared.edition(id: summary.id)
        if settings.isOn(.quickAdd) || settings.isOn(.librarySection) {
            await collection.load()
        }
        edition = await details
        failed = edition == nil
        if route.offersLibraryLink {
            plexMatch = await PlexDiscMatcher.match(title: summary.title, year: summary.year ?? edition?.year)
        }
    }

    // MARK: - Layouts

    private var wideLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                EditionIdentity(summary: summary, edition: edition, layout: .sidebar,
                                plexMatch: plexMatch, onOpenPlex: openPlex, onZoom: zoom)
                    .frame(width: sidebarWidth, alignment: .leading)
                    .padding(.leading, gutter)
                    .padding(.trailing, DS.Space.s32)
                    .padding(.vertical, DS.Space.s32)
            }
            .frame(width: gutter + sidebarWidth + DS.Space.s32)

            Rectangle()
                .fill(theme.separator)
                .frame(width: DS.Border.thin)
                .padding(.vertical, DS.Space.s32)

            ScrollView {
                contentColumn
                    .padding(.leading, DS.Space.s40)
                    .padding(.trailing, gutter)
                    .padding(.vertical, DS.Space.s32)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var stackedLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s40) {
                EditionIdentity(summary: summary, edition: edition, layout: .header,
                                plexMatch: plexMatch, onOpenPlex: openPlex, onZoom: zoom)
                contentColumn
            }
            .padding(.horizontal, gutter)
            .padding(.vertical, DS.Space.s32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func openPlex(_ media: MediaItem) {
        router.push(DetailsNavigationItem(item: media), on: mainViewState.selectedTab)
    }

    /// The cover alone in the image viewer.
    private func zoom(_ url: URL?) {
        guard let url else { return }
        ImageViewerPresenter.shared.show([ImageViewerItem(url: url, caption: summary.title)])
    }

    private func showScreenshots(_ edition: MBEdition, at index: Int) {
        let items = edition.screenshots.compactMap { shot -> ImageViewerItem? in
            guard let url = URL(string: shot.url) else { return nil }
            return ImageViewerItem(url: url, thumbnail: shot.thumbnailUrl.flatMap(URL.init(string:)))
        }
        ImageViewerPresenter.shared.show(items, at: index)
    }

    private func showArtwork(_ art: [MBEdition.Artwork], at index: Int) {
        let items = art.compactMap { item -> ImageViewerItem? in
            URL(string: item.url).map { ImageViewerItem(url: $0, caption: Self.artworkLabel(item.type)) }
        }
        ImageViewerPresenter.shared.show(items, at: index)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentColumn: some View {
        if let edition {
            VStack(alignment: .leading, spacing: DS.Space.sectionGap) {
                if let synopsis = edition.metadata?.synopsis, !synopsis.isEmpty,
                   !synopsis.lowercased().hasPrefix("see individual titles") {
                    section("About") { ExpandableText(text: synopsis, collapsedLineLimit: 4) }
                }
                if settings.isOn(.editionScores), let scores = edition.reviewScores, EditionScores.hasAny(scores) {
                    section("Review Scores") { EditionScores(scores: scores) }
                }
                if settings.isOn(.editionSpecs), !specFacts(edition).isEmpty || !(edition.audio ?? []).isEmpty {
                    section("Video & Audio") { EditionSpecs(edition: edition, videoFacts: specFacts(edition)) }
                }
                if settings.isOn(.editionScreenshots), !edition.screenshots.isEmpty {
                    section("Screenshots") { screenshots(edition) }
                }
                if settings.isOn(.editionArtwork), !edition.artwork.isEmpty {
                    section("Artwork") { artwork(edition) }
                }
                if (settings.isOn(.editionDigitalCopy) && edition.digitalCopy?.included == true)
                    || (settings.isOn(.editionPrice) && edition.metadata?.amazon?.price != nil) {
                    section("Digital Copy & Price") { digitalAndPrice(edition) }
                }
            }
        } else if failed {
            BrowseMessageView(systemImage: "opticaldisc", title: "Couldn't load this edition",
                              message: "MyBluray didn't answer. Try again in a moment.",
                              retryTitle: "Try Again", onRetry: { Task { await load() } })
        } else {
            VStack(alignment: .leading, spacing: DS.Space.s16) {
                SkeletonView(width: 180, height: 22, cornerRadius: DS.Radius.badge)
                ForEach(0..<6, id: \.self) { index in
                    SkeletonView(height: 14, cornerRadius: DS.Radius.badge)
                        .frame(maxWidth: index == 5 ? 260 : .infinity, alignment: .leading)
                }
            }
        }
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s14) {
            Text(title)
                .flixorFont(.title2)
                .foregroundStyle(theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func specFacts(_ edition: MBEdition) -> [PersonFact] {
        var facts: [PersonFact] = []
        func add(_ label: String, _ value: String?) {
            if let value, !value.isEmpty { facts.append(PersonFact(label: label, value: value)) }
        }
        add(String(localized: "Video"), edition.video?.codec)
        add(String(localized: "Resolution"), edition.video?.resolution)
        add(String(localized: "HDR"), edition.video?.hdr)
        add(String(localized: "Aspect ratio"), [edition.video?.aspectRatio, edition.video?.originalAspectRatio.map { String(localized: "original \($0)") }]
            .compactMap { $0 }.joined(separator: " · "))
        return facts
    }

    private func screenshots(_ edition: MBEdition) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s10) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: DS.Space.s12)], alignment: .leading, spacing: DS.Space.s12) {
                ForEach(Array(edition.screenshots.enumerated()), id: \.offset) { index, shot in
                    Button { showScreenshots(edition, at: index) } label: {
                        Color.clear
                            .aspectRatio(16 / 9, contentMode: .fit)
                            .overlay(CachedAsyncImage(url: URL(string: shot.thumbnailUrl ?? shot.url), contentMode: .fill) { Color.clear })
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: DS.Radius.r8, style: .continuous)
                                .strokeBorder(theme.separator, lineWidth: DS.Border.thin))
                    }
                    .buttonStyle(.plain)
                    .help("Show larger")
                }
            }
            if let note = edition.screenshots.first?.provenance?.note, !note.isEmpty {
                Text(note).flixorFont(.caption).foregroundStyle(theme.textTertiary)
            }
        }
    }

    private func artwork(_ edition: MBEdition) -> some View {
        // Blu-ray.com lists the front cover at several sizes; keep one of each kind.
        var seen = Set<String>()
        let unique = edition.artwork.filter { seen.insert($0.type ?? $0.url).inserted }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: DS.Space.s16) {
                ForEach(Array(unique.enumerated()), id: \.offset) { index, art in
                    VStack(alignment: .leading, spacing: DS.Space.s6) {
                        Button { showArtwork(unique, at: index) } label: {
                            CachedAsyncImage(url: URL(string: art.url))
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 180)
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        PersonSectionLabel(text: .init(Self.artworkLabel(art.type)))
                    }
                }
            }
            .padding(.vertical, DS.Space.s4)
        }
    }

    private static func artworkLabel(_ type: String?) -> String {
        switch type {
        case "front-cover": return String(localized: "Front")
        case "back-cover": return String(localized: "Back")
        case "slipcover-front": return String(localized: "Slipcover")
        case "slipcover-back": return String(localized: "Slipcover back")
        case "packaging-overview": return String(localized: "Packaging")
        default: return (type ?? "").replacingOccurrences(of: "-", with: " ").capitalized
        }
    }

    @ViewBuilder
    private func digitalAndPrice(_ edition: MBEdition) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s40) {
            if settings.isOn(.editionDigitalCopy), let copy = edition.digitalCopy, copy.included == true {
                VStack(alignment: .leading, spacing: DS.Space.s8) {
                    PersonSectionLabel(text: copy.resolution.map { "Digital copy · \($0.uppercased())" } ?? "Digital copy")
                    HStack(spacing: DS.Space.controlGap) {
                        ForEach(Array(copy.platforms.enumerated()), id: \.offset) { _, platform in
                            Text(platform.label ?? platform.value ?? "")
                                .flixorFont(.footnote, weight: .semibold)
                                .foregroundStyle(theme.textSecondary)
                                .padding(.horizontal, DS.Space.s12)
                                .padding(.vertical, DS.Space.s6)
                                .background(Capsule().fill(theme.hoverFill))
                                .overlay(Capsule().strokeBorder(theme.separator, lineWidth: DS.Border.thin))
                        }
                        if copy.platforms.isEmpty {
                            Text("Included").flixorFont(.body).foregroundStyle(theme.textSecondary)
                        }
                    }
                }
            }
            if settings.isOn(.editionPrice), let offer = edition.metadata?.amazon, let price = offer.price {
                VStack(alignment: .leading, spacing: DS.Space.s8) {
                    PersonSectionLabel(text: offer.availability.map { "Price · \($0)" } ?? "Price")
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s10) {
                        Text("\(offer.currency ?? "")\(price)")
                            .flixorFont(.title2)
                            .foregroundStyle(theme.textPrimary)
                        if let list = offer.listPrice, list != price {
                            Text("\(offer.currency ?? "")\(list)")
                                .flixorFont(.callout)
                                .strikethrough()
                                .foregroundStyle(theme.textTertiary)
                        }
                        if let url = offer.purchaseUrl.flatMap(URL.init(string:)) {
                            EditionLinkButton(title: "Amazon", systemImage: "cart", url: url)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Specs

/// Video facts in two columns, then audio and subtitles in full. Box sets
/// list audio per film ("Batman Begins 4K", then its tracks); subtitles come
/// as one run-together string, split back up by those film names.
private struct EditionSpecs: View {
    let edition: MBEdition
    let videoFacts: [PersonFact]

    @Environment(\.flixorTheme) private var theme

    /// Film names in a box set's audio list (entries with no "Language: format").
    private var discTitles: [String] { (edition.audio ?? []).filter { !$0.contains(":") } }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s20) {
            if !videoFacts.isEmpty { PersonFactsList(facts: videoFacts, columns: 2) }
            if let audio = edition.audio, !audio.isEmpty {
                group("Audio", lines: audio)
            }
            if let subtitles = edition.subtitles, !subtitles.isEmpty {
                group("Subtitles", lines: Self.split(subtitles, titles: discTitles))
            }
        }
    }

    /// Lines without a colon are film names in a box set, shown as subheadings.
    private func group(_ label: LocalizedStringKey, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            PersonSectionLabel(text: label)
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                if discTitles.contains(line) {
                    Text(line)
                        .flixorFont(.callout, weight: .semibold)
                        .foregroundStyle(theme.textPrimary)
                        .padding(.top, index == 0 ? 0 : DS.Space.s6)
                } else {
                    Text(line)
                        .flixorFont(.body)
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
    }

    /// "Batman Begins 4K English, FrenchThe Dark Knight 4K English" →
    /// ["Batman Begins 4K", "English, French", "The Dark Knight 4K", "English"].
    static func split(_ text: String, titles: [String]) -> [String] {
        // MyBluray now sends one line per film and per language list.
        if text.contains("\n") {
            return text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        guard !titles.isEmpty else { return [text] }
        var lines: [String] = []
        var rest = Substring(text)
        while !rest.isEmpty {
            // The next film name, if any, after the start.
            let next = titles.compactMap { title -> (Range<Substring.Index>, String)? in
                rest.range(of: title).map { ($0, title) }
            }.min { $0.0.lowerBound < $1.0.lowerBound }
            guard let (range, title) = next else {
                lines.append(rest.trimmingCharacters(in: .whitespaces))
                break
            }
            let before = rest[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            if !before.isEmpty { lines.append(before) }
            lines.append(title)
            rest = rest[range.upperBound...]
        }
        return lines.filter { !$0.isEmpty }
    }
}

// MARK: - Identity (sidebar / header)

private struct EditionIdentity: View {
    enum Layout { case sidebar, header }

    let summary: MBEditionSummary
    let edition: MBEdition?
    let layout: Layout
    let plexMatch: MediaItem?
    let onOpenPlex: (MediaItem) -> Void
    let onZoom: (URL?) -> Void

    @Environment(\.flixorTheme) private var theme
    @ObservedObject private var settings = MyBluraySettingsStore.shared
    @ObservedObject private var collection = PhysicalCollectionStore.shared

    var body: some View {
        switch layout {
        case .sidebar:
            VStack(alignment: .leading, spacing: DS.Space.s24) {
                cover(width: 220)
                titleBlock(font: .largeTitle)
                actions
                PersonFactsList(facts: facts)
                links
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .header:
            HStack(alignment: .top, spacing: DS.Space.s28) {
                cover(width: 170)
                VStack(alignment: .leading, spacing: DS.Space.s16) {
                    titleBlock(font: .display)
                    actions
                    PersonFactsList(facts: facts, columns: 2)
                    links
                }
                .padding(.top, DS.Space.s4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func cover(width: CGFloat) -> some View {
        Button { onZoom(summary.coverImage.flatMap(URL.init(string:))) } label: {
            CachedAsyncImage(url: summary.coverImage.flatMap(URL.init(string:)))
                .aspectRatio(contentMode: .fill)
                .frame(width: width, height: (width * EditionCoverCard.aspect).rounded())
                .clipped()
                .background(theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.r8, style: .continuous)
                    .stroke(theme.separatorStrong, lineWidth: DS.Border.thin))
                .flixorShadow(.card)
        }
        .buttonStyle(.plain)
        .help("Show larger")
    }

    private func titleBlock(font: FlixorType) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            PersonSectionLabel(text: .init(summary.isUHD ? "4K Ultra HD" : "Blu-ray"))
            Text(summary.baseTitle.isEmpty ? (edition?.title ?? "") : summary.baseTitle)
                .flixorFont(font)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(3)
                .textSelection(.enabled)
                .accessibilityAddTraits(.isHeader)
            Text(edition?.editionTitle.flatMap { $0.isEmpty ? nil : $0 } ?? summary.editionName)
                .flixorFont(.headline)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(3)
        }
    }

    @ViewBuilder private var actions: some View {
        let canEdit = settings.isOn(.quickAdd) && collection.isConnected && !collection.lists.isEmpty
        if canEdit || plexMatch != nil {
            HStack(spacing: DS.Space.controlGap) {
                if canEdit { collectionMenu }
                if let plexMatch {
                    BrowsePillButton(title: String(localized: "Open in Library"), systemImage: "play.fill") { onOpenPlex(plexMatch) }
                }
            }
            if let message = collection.message {
                Text(message).flixorFont(.caption).foregroundStyle(theme.textTertiary)
            }
        }
    }

    private var collectionMenu: some View {
        let current = collection.listFor[summary.id]
        return Menu {
            CollectionMenuItems(edition: summary, list: current)
        } label: {
            HStack(spacing: DS.Space.s6) {
                Image(systemName: current == nil ? "plus" : "checkmark")
                    .font(.flixorIcon(DS.Icon.xs, weight: .bold))
                Text(current?.name ?? String(localized: "Add to Collection"))
                    .flixorFont(.callout, weight: .semibold)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .opacity(0.6)
            }
            .foregroundStyle(current == nil ? Color.black : theme.textPrimary)
            .padding(.horizontal, DS.Space.s14)
            .frame(height: 32)
            .background(Capsule().fill(current == nil ? Color.white : theme.hoverFill))
            .overlay(Capsule().strokeBorder(current == nil ? Color.clear : theme.separator, lineWidth: DS.Border.thin))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var facts: [PersonFact] {
        var facts: [PersonFact] = []
        func add(_ label: String, _ value: String?) {
            if let value, !value.isEmpty { facts.append(PersonFact(label: label, value: value)) }
        }
        add(String(localized: "Released"), summary.releaseDateText)
        add(String(localized: "Country"), (edition?.country ?? summary.country)?.name)
        add(String(localized: "Studio"), edition?.metadata?.studio)
        if let runtime = edition?.metadata?.runtime, runtime > 0 {
            add(String(localized: "Runtime"), runtime >= 60 ? "\(runtime / 60)h \(runtime % 60)m" : "\(runtime) min")
        }
        add(String(localized: "Discs"), edition?.discs?.joined(separator: " · "))
        add(String(localized: "Region"), edition?.region?.joined(separator: " · "))
        add(String(localized: "Packaging"), edition?.packaging?.joined(separator: " · "))
        add(String(localized: "Exclusive"), edition?.exclusive)
        return facts
    }

    @ViewBuilder private var links: some View {
        if settings.isOn(.editionLinks), let edition {
            HStack(spacing: DS.Space.controlGap) {
                if let site = edition.websiteUrl.flatMap(URL.init(string:)) {
                    EditionLinkButton(title: "Blu-ray.com", systemImage: "opticaldisc", url: site)
                }
                if let review = edition.reviewScores?.critic?.sourceUrl.flatMap(URL.init(string:)) {
                    EditionLinkButton(title: String(localized: "Review"), systemImage: "text.quote", url: review)
                }
            }
        }
    }
}

/// Capsule link, like the person page's IMDb / website buttons.
private struct EditionLinkButton: View {
    let title: String
    let systemImage: String
    let url: URL

    @Environment(\.flixorTheme) private var theme
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button { openURL(url) } label: {
            Label(title, systemImage: systemImage)
                .flixorFont(.footnote, weight: .semibold)
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal, DS.Space.s10)
                .padding(.vertical, DS.Space.s6)
                .background(Capsule().fill(theme.hoverFill))
                .overlay(Capsule().stroke(theme.separator, lineWidth: DS.Border.thin))
        }
        .buttonStyle(.plain)
        .help(url.absoluteString)
    }
}

// MARK: - Scores

/// Blu-ray.com's scores as cards: the critic's review, community reviews and
/// community ratings, each rating the movie, picture, sound and extras.
private struct EditionScores: View {
    let scores: MBEdition.ReviewScores

    @Environment(\.flixorTheme) private var theme

    private static let keys: [(String, String)] = [
        ("overall", "Overall"), ("movie", "Movie"), ("video4k", "4K video"), ("video2k", "1080p video"),
        ("video", "Video"), ("audio", "Audio"), ("extras", "Extras"),
    ]

    static func hasAny(_ scores: MBEdition.ReviewScores) -> Bool {
        [scores.critic, scores.communityReviews, scores.communityRatings].contains { !($0?.scores ?? [:]).isEmpty }
    }

    var body: some View {
        let cards: [(String, MBEdition.ScoreSet)] = [
            (String(localized: "Critic review"), scores.critic),
            (String(localized: "Community reviews"), scores.communityReviews),
            (String(localized: "Community ratings"), scores.communityRatings),
        ].compactMap { label, set in
            guard let set, !(set.scores ?? [:]).isEmpty else { return nil }
            return (label, set)
        }
        HStack(alignment: .top, spacing: DS.Space.s16) {
            ForEach(cards, id: \.0) { card in
                VStack(alignment: .leading, spacing: DS.Space.s10) {
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        PersonSectionLabel(text: .init(card.0))
                        Text(Self.byline(card.1))
                            .flixorFont(.caption)
                            .foregroundStyle(theme.textTertiary)
                    }
                    ForEach(Self.keys.filter { card.1.scores?[$0.0] != nil }, id: \.0) { key in
                        HStack {
                            Text(key.1).flixorFont(.callout).foregroundStyle(theme.textSecondary)
                            Spacer(minLength: DS.Space.s8)
                            StarScore(value: card.1.scores?[key.0] ?? 0, scale: card.1.scale ?? 5)
                        }
                    }
                }
                .padding(DS.Space.cardPadding)
                .frame(maxWidth: 300, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).fill(theme.surfaceOverlay))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .strokeBorder(theme.separator, lineWidth: DS.Border.thin))
            }
        }
    }

    private static func byline(_ set: MBEdition.ScoreSet) -> String {
        if let author = set.author { return String(localized: "by \(author)") }
        if let votes = set.voteCount { return votes == 1 ? String(localized: "1 vote") : String(localized: "\(votes) votes") }
        return " "
    }
}

private struct StarScore: View {
    let value: Double
    let scale: Double

    @Environment(\.flixorTheme) private var theme

    var body: some View {
        HStack(spacing: DS.Space.s4) {
            Image(systemName: "star.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color(hex: "F5C518"))
            Text(String(format: value.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", value))
                .flixorFont(.callout, weight: .semibold)
                .foregroundStyle(theme.textPrimary)
            Text("/ \(Int(scale))")
                .flixorFont(.caption)
                .foregroundStyle(theme.textTertiary)
        }
    }
}
