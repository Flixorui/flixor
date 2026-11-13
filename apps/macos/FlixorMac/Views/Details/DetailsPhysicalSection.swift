//
//  DetailsPhysicalSection.swift
//  FlixorMac
//
//  Physical Releases on Details (movies only), from MyBluray / Blu-ray.com:
//  the film's Blu-ray and 4K editions for the chosen market, falling back to
//  every market when that one has none. Covers carry no badges; the caption
//  says the format, release and whether the disc is in the collection, and a
//  hover menu adds it to a list when a Blu-ray.com login is on the key.
//  Clicking a cover opens the edition page.
//

import SwiftUI

// MARK: - Model

@MainActor
final class DetailsPhysicalModel: ObservableObject {
    enum Phase: Equatable { case idle, loading, loaded, empty }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var editions: [MBEditionSummary] = []
    /// The film on Blu-ray.com, for the "Blu-ray.com" link and IMDb id.
    @Published private(set) var movie: MBMovie?
    /// The market shown, or nil when it fell back to every market.
    @Published private(set) var country: String?
    @Published private(set) var usedFallback = false

    private var loadedKey: String?

    /// Loads (once per title and settings) when the section can appear.
    func load(imdbId: String?, settings: MyBluraySettingsStore) async {
        guard let imdbId, settings.isOn(.physicalReleases) else {
            reset()
            return
        }
        var formats: [String] = []
        if settings.isOn(.uhdFormat) { formats.append("4k") }
        if settings.isOn(.blurayFormat) { formats.append("bluray") }
        guard !formats.isEmpty else {
            reset()
            return
        }
        let market = settings.effectiveDiscCountry
        let boxSets = settings.isOn(.boxSets)
        let key = "\(imdbId)|\(market ?? "all")|\(formats.joined(separator: ","))|\(boxSets)"
        guard key != loadedKey else { return }
        loadedKey = key
        phase = .loading
        editions = []
        usedFallback = false

        let service = MyBlurayService.shared
        guard let movie = try? await service.movie(imdbId: imdbId) else {
            if loadedKey == key { phase = .empty }
            return
        }
        guard loadedKey == key else { return }
        self.movie = movie

        var found = (try? await service.editions(movieId: movie.id, country: market, formats: formats)) ?? []
        var shownCountry = market
        if !boxSets { found = found.filter { $0.bundle != true } }
        if found.isEmpty, market != nil {
            // Some films only came out elsewhere (Dhoom is India-only).
            found = (try? await service.editions(movieId: movie.id, country: nil, formats: formats)) ?? []
            if !boxSets { found = found.filter { $0.bundle != true } }
            shownCountry = nil
            usedFallback = !found.isEmpty
        }
        guard loadedKey == key else { return }
        editions = Self.sorted(found)
        country = shownCountry
        phase = editions.isEmpty ? .empty : .loaded

        if settings.isOn(.quickAdd) || settings.isOn(.librarySection) {
            await PhysicalCollectionStore.shared.load()
        }
    }

    func reset() {
        loadedKey = nil
        phase = .idle
        editions = []
        movie = nil
        usedFallback = false
    }

    /// 4K first, then Blu-ray; newest first within each.
    private static func sorted(_ editions: [MBEditionSummary]) -> [MBEditionSummary] {
        editions.sorted { a, b in
            let fa = a.format == "4k" ? 0 : 1, fb = b.format == "4k" ? 0 : 1
            if fa != fb { return fa < fb }
            return (a.releaseDate ?? "") > (b.releaseDate ?? "")
        }
    }
}

// MARK: - Section

struct DetailsPhysicalSection: View {
    @ObservedObject var model: DetailsPhysicalModel
    let onSelect: (MBEditionSummary) -> Void

    @Environment(\.flixorTheme) private var theme
    @ObservedObject private var collection = PhysicalCollectionStore.shared

    private enum Filter: Hashable { case all, uhd, bluray }
    @State private var filter: Filter = .all

    private static let cardWidth: CGFloat = 150

    private var shown: [MBEditionSummary] {
        switch filter {
        case .all: return model.editions
        case .uhd: return model.editions.filter { $0.format == "4k" }
        case .bluray: return model.editions.filter { $0.format != "4k" }
        }
    }

    private var hasBothFormats: Bool {
        model.editions.contains { $0.format == "4k" } && model.editions.contains { $0.format != "4k" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DetailsSectionStyle.headingGap) {
            HStack(alignment: .center, spacing: DS.Space.s12) {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    DetailsSectionHeading("Physical Releases")
                    Text(subtitle)
                        .flixorFont(.caption)
                        .foregroundStyle(theme.textTertiary)
                }
                Spacer(minLength: DS.Space.s8)
                if hasBothFormats {
                    FlixorSegmentedControl(
                        items: [
                            .init(value: Filter.all, title: String(localized: "All")),
                            .init(value: Filter.uhd, title: "4K"),
                            .init(value: Filter.bluray, title: "Blu-ray"),
                        ],
                        selection: $filter,
                        height: 30
                    )
                }
                if let link = model.movie?.websiteUrl.flatMap(URL.init(string:)) {
                    Link(destination: link) {
                        Label("Blu-ray.com", systemImage: "arrow.up.right")
                            .labelStyle(.titleAndIcon)
                            .flixorFont(.footnote, weight: .semibold)
                            .foregroundStyle(theme.textSecondary)
                            .padding(.horizontal, DS.Space.s12)
                            .frame(height: 30)
                            .background(Capsule().fill(theme.hoverFill))
                            .overlay(Capsule().strokeBorder(theme.separator, lineWidth: DS.Border.thin))
                    }
                    .buttonStyle(.plain)
                    .help(link.absoluteString)
                }
            }

            DetailsHorizontalRow {
                LazyHStack(alignment: .top, spacing: DS.Space.s16) {
                    ForEach(shown) { edition in
                        EditionCoverCard(edition: edition, width: Self.cardWidth, showsList: true,
                                         showsCountry: model.country == nil) {
                            onSelect(edition)
                        }
                    }
                }
                .padding(.vertical, DS.Space.s4)
            }

            if let message = collection.message {
                Text(message)
                    .flixorFont(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .task(id: message) {
                        guard message != String(localized: "Saving…") else { return }
                        try? await Task.sleep(nanoseconds: 4_000_000_000)
                        if collection.message == message { collection.message = nil }
                    }
            }
        }
    }

    private var subtitle: String {
        let count = model.editions.count
        let editions = count == 1 ? String(localized: "1 edition") : String(localized: "\(count) editions")
        if model.usedFallback { return editions + " · " + String(localized: "none in your country, showing all") }
        if let code = model.country {
            let name = MyBluraySettingsStore.discCountries.first(where: { $0.code == code })?.name ?? code
            return editions + " · " + name
        }
        return editions + " · " + String(localized: "all countries")
    }
}

// MARK: - Cover card

/// A disc cover in the poster-card style: no badges on the art, a caption
/// with the edition, format, release and collection list, and (with a
/// Blu-ray.com login) a hover menu to add, move or remove it.
struct EditionCoverCard: View {
    let edition: MBEditionSummary
    let width: CGFloat
    /// Say in the caption which list the disc is in.
    var showsList = true
    var showsCountry = false
    let onSelect: () -> Void

    @Environment(\.flixorTheme) private var theme
    @ObservedObject private var cardStyle = CardStyleStore.shared
    @ObservedObject private var collection = PhysicalCollectionStore.shared
    @ObservedObject private var settings = MyBluraySettingsStore.shared
    @State private var isHovered = false

    /// Blu-ray cases are wider than film posters.
    static let aspect: CGFloat = 1.26

    private var height: CGFloat { (width * Self.aspect).rounded() }
    private var radius: CGFloat { cardStyle.cornerStyle.posterRadius }
    private var list: MBCollectionEntry.ListRef? { collection.listFor[edition.id] }
    private var canEdit: Bool { settings.isOn(.quickAdd) && collection.isConnected && !collection.lists.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s8) {
            Button(action: onSelect) {
                CachedAsyncImage(url: edition.coverImage.flatMap(URL.init(string:)))
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipped()
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .stroke(Color.white.opacity(isHovered ? 0.9 : 0.15), lineWidth: isHovered ? 2 : 1)
                    )
            }
            .buttonStyle(.plain)
            .overlay(alignment: .topTrailing) {
                if canEdit && isHovered {
                    CollectionMenuButton(edition: edition, list: list)
                        .padding(DS.Space.s8)
                        .transition(.opacity)
                }
            }

            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text(edition.editionName)
                    .font(.flixor(.callout, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(2)
                    .frame(width: width, alignment: .leading)
                HStack(spacing: DS.Space.s4) {
                    if showsList, let list {
                        Image(systemName: list.alias == "owned" ? "checkmark.circle.fill" : "bookmark.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(theme.textSecondary)
                        Text(list.name ?? "").foregroundStyle(theme.textSecondary)
                        Text("·")
                    }
                    Text(caption)
                }
                .font(.flixor(.caption))
                .foregroundStyle(theme.textTertiary)
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
            }
        }
        .frame(width: width)
        .onHover { hovering in withAnimation(DS.Motion.quick) { isHovered = hovering } }
        .help(edition.title ?? "")
    }

    private var caption: String {
        var parts = [edition.formatName]
        if let date = edition.releaseDateText { parts.append(date) }
        if showsCountry, let code = edition.country?.code { parts.append(code) }
        if edition.bundle == true { parts.append(String(localized: "Box set")) }
        return parts.joined(separator: " · ")
    }
}

/// Round 26pt button on a cover: add to a list, move it, or remove it.
struct CollectionMenuButton: View {
    let edition: MBEditionSummary
    let list: MBCollectionEntry.ListRef?

    var body: some View {
        Menu {
            CollectionMenuItems(edition: edition, list: list)
        } label: {
            Image(systemName: list == nil ? "plus" : "ellipsis")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.black.opacity(0.7)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: DS.Border.thin))
                .contentShape(Circle())
        }
        // .button + .plain keeps the label as drawn (the borderless style drops its circle).
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(list.map { String(localized: "In \($0.name ?? "your collection")") } ?? String(localized: "Add to collection"))
    }
}

/// The lists, with the current one ticked, then Remove.
struct CollectionMenuItems: View {
    let edition: MBEditionSummary
    let list: MBCollectionEntry.ListRef?

    @ObservedObject private var collection = PhysicalCollectionStore.shared

    var body: some View {
        Section(list == nil ? String(localized: "Add to") : String(localized: "Move to")) {
            ForEach(collection.lists) { option in
                Button {
                    Task { await collection.add(edition, to: option) }
                } label: {
                    if list?.id == option.id {
                        Label(option.name ?? option.id, systemImage: "checkmark")
                    } else {
                        Text(option.name ?? option.id)
                    }
                }
                .disabled(list?.id == option.id)
            }
        }
        if list != nil {
            Divider()
            Button(String(localized: "Remove from Collection"), role: .destructive) {
                Task { await collection.remove(edition) }
            }
        }
    }
}

// MARK: - Edition text

extension MBEditionSummary {
    /// The edition's own name: "Bat-Pod Display Case | Limited Edition" from
    /// "The Dark Knight (Bat-Pod Display Case | Limited Edition)", else the
    /// title (which may say "4K"), else "Standard Edition".
    var editionName: String {
        let raw = title ?? ""
        if let open = raw.firstIndex(of: "("), raw.hasSuffix(")") {
            let inner = raw[raw.index(after: open)..<raw.index(before: raw.endIndex)]
            if !inner.isEmpty { return String(inner) }
        }
        return raw.isEmpty ? String(localized: "Standard Edition") : raw
    }

    /// The film's title without the edition: "The Dark Knight Trilogy 4K".
    var baseTitle: String {
        let raw = title ?? ""
        guard let open = raw.firstIndex(of: "(") else { return raw }
        return raw[..<open].trimmingCharacters(in: .whitespaces)
    }

    var isUHD: Bool {
        format == "4k" || (title ?? "").range(of: #"\b4K\b"#, options: .regularExpression) != nil
    }

    var formatName: String { isUHD ? "4K" : "Blu-ray" }

    /// "Dec 19, 2017". The day is shown as given, not moved into the local
    /// time zone (which turned Dec 19 into Dec 18 in the US).
    var releaseDateText: String? {
        guard let releaseDate, let date = Self.isoDay.date(from: releaseDate) else { return nil }
        return Self.display.string(from: date)
    }

    private static let isoDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private static let display: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}
