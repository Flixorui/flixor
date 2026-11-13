//
//  DetailsInfoSections.swift
//  FlixorMac
//
//  Details section: about, production/networks, info, technical details, collections
//

import SwiftUI
import FlixorKit

struct DetailsTabContent: View {
    @ObservedObject var vm: DetailsViewModel
    let layout: DetailsLayoutMetrics
    var onEntityTap: (EntityBrowseRoute) -> Void = { _ in }
    /// The Parents Guide already shows the age rating (with its reason).
    var hidesContentRating = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s40) {
            // About Section (Apple TV+ style cards) - moved above Cast & Crew
            VStack(alignment: .leading, spacing: DetailsSectionStyle.headingGap) {
                DetailsSectionHeading("About")

                // Tagline (if available)
                if let tagline = vm.tagline, !tagline.isEmpty {
                    Text("\"\(tagline)\"")
                        .font(.flixor(.bodyLarge, weight: .regular))
                        .italic()
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.bottom, DS.Space.s4)
                }

                HStack(alignment: .top, spacing: DS.Space.s16) {
                    // Main info card
                    VStack(alignment: .leading, spacing: DS.Space.s12) {
                        Text(vm.title)
                            .font(.flixor(.title3, weight: .semibold))
                            .foregroundStyle(.white)

                        if !vm.genres.isEmpty {
                            Text(vm.genres.joined(separator: ", ").uppercased())
                                .font(.flixor(.footnote, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))
                        }

                        if !vm.overview.isEmpty {
                            Text(vm.overview)
                                .font(.flixor(.body))
                                .lineSpacing(4)
                                .foregroundStyle(.white.opacity(0.85))
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(DS.Space.s20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.r12, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )

                    // Content rating card - height matches description card
                    if let rating = vm.rating, !hidesContentRating {
                        VStack(alignment: .leading, spacing: DS.Space.s8) {
                            HStack(spacing: DS.Space.s8) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                                    .font(.flixor(.title3))
                                Text(rating)
                                    .font(.flixor(.title1, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            Text("CONTENT RATING")
                                .font(.flixor(.caption, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))
                            Spacer(minLength: 0)
                        }
                        .padding(DS.Space.s20)
                        .frame(width: 200)
                        .frame(maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.r12, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            // Production Section (Movies) - with logos; tapping browses the company
            if vm.mediaKind == "movie" && !vm.productionCompanies.isEmpty {
                DetailsEntityLogoRow(
                    title: "Production",
                    kind: .company,
                    entities: Array(vm.productionCompanies.prefix(6)),
                    onTap: onEntityTap
                )
            }

            // Networks Section (TV) - with logos; tapping browses the network
            if vm.mediaKind == "tv" && !vm.networks.isEmpty {
                DetailsEntityLogoRow(
                    title: "Networks",
                    kind: .network,
                    entities: Array(vm.networks.prefix(6)),
                    onTap: onEntityTap
                )
            }

            // Three-column info section (Apple TV+ style)
            HStack(alignment: .top, spacing: DS.Space.s40) {
                // Information column
                VStack(alignment: .leading, spacing: DS.Space.s20) {
                    Text("Information")
                        .font(.flixor(.title3, weight: .semibold))
                        .foregroundStyle(.white)

                    VStack(alignment: .leading, spacing: DS.Space.s16) {
                        // Episode-specific info
                        if vm.isEpisode {
                            if let showTitle = vm.showTitle {
                                InfoRow(label: "Show", value: showTitle)
                            }

                            if let sNum = vm.seasonNumber, let eNum = vm.episodeNumber {
                                InfoRow(label: "Episode", value: String(localized: "Season \(String(sNum)), Episode \(String(eNum))"))
                            }

                            if let airDate = vm.airDate, !airDate.isEmpty {
                                InfoRow(label: "Air Date", value: formatAirDate(airDate))
                            }

                            if let rating = vm.tmdbRating, rating > 0 {
                                InfoRow(label: "TMDB Rating", value: String(format: "%.1f/10", rating))
                            }

                            if let director = vm.episodeDirector {
                                InfoRow(label: "Directed By", value: director)
                            }

                            if let writer = vm.episodeWriter {
                                InfoRow(label: "Written By", value: writer)
                            }
                        }

                        if let year = vm.year {
                            InfoRow(label: "Released", value: year)
                        }

                        if let runtime = vm.runtime {
                            InfoRow(label: "Run Time", value: formattedRuntime(runtime))
                        }

                        if let rating = vm.rating {
                            InfoRow(label: "Rated", value: rating)
                        }

                        if let status = vm.status, !vm.isEpisode {
                            InfoRow(label: "Status", value: status)
                        }

                        if vm.mediaKind == "tv" && !vm.isEpisode {
                            if let seasons = vm.numberOfSeasons {
                                InfoRow(label: "Seasons", value: "\(seasons)")
                            }
                            if let episodes = vm.numberOfEpisodes {
                                InfoRow(label: "Episodes", value: "\(episodes)")
                            }
                        }

                        if vm.mediaKind == "movie" {
                            if let budget = vm.budget {
                                InfoRow(label: "Budget", value: formatCurrency(budget))
                            }
                            if let revenue = vm.revenue {
                                InfoRow(label: "Box Office", value: formatCurrency(revenue))
                            }
                        }

                        if let lang = vm.originalLanguage, !vm.isEpisode {
                            InfoRow(label: "Original Language", value: languageName(for: lang))
                        }

                        if let studio = vm.studio, !vm.isEpisode {
                            InfoRow(label: "Studio", value: studio)
                        }

                        if vm.mediaKind == "tv" && !vm.creators.isEmpty && !vm.isEpisode {
                            InfoRow(label: "Created By", value: vm.creators.joined(separator: ", "))
                        }

                        // Directors (for non-episodes - episodes have episodeDirector above)
                        if !vm.directors.isEmpty && !vm.isEpisode {
                            InfoRow(label: "Directed By", value: vm.directors.joined(separator: ", "))
                        }

                        // Writers (for non-episodes)
                        if !vm.writers.isEmpty && !vm.isEpisode {
                            InfoRow(label: "Written By", value: vm.writers.joined(separator: ", "))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Languages column
                VStack(alignment: .leading, spacing: DS.Space.s20) {
                    Text("Languages")
                        .font(.flixor(.title3, weight: .semibold))
                        .foregroundStyle(.white)

                    VStack(alignment: .leading, spacing: DS.Space.s16) {
                        if let lang = vm.originalLanguage {
                            InfoRow(label: "Original Audio", value: languageName(for: lang))
                        }

                        if !vm.audioTracks.isEmpty {
                            VStack(alignment: .leading, spacing: DS.Space.s4) {
                                Text("Audio")
                                    .font(.flixor(.callout, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.5))
                                Text(vm.audioTracks.map { $0.name }.joined(separator: ", "))
                                    .font(.flixor(.body))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .lineLimit(4)
                            }
                        }

                        if !vm.subtitleTracks.isEmpty {
                            VStack(alignment: .leading, spacing: DS.Space.s4) {
                                Text("Subtitles")
                                    .font(.flixor(.callout, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.5))
                                Text(vm.subtitleTracks.map { $0.name }.joined(separator: ", "))
                                    .font(.flixor(.body))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .lineLimit(6)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Technical / Production column
                VStack(alignment: .leading, spacing: DS.Space.s20) {
                    Text("Technical")
                        .font(.flixor(.title3, weight: .semibold))
                        .foregroundStyle(.white)

                    VStack(alignment: .leading, spacing: DS.Space.s16) {
                        if let version = vm.activeVersionDetail {
                            if let res = version.technical.resolution {
                                InfoRow(label: "Resolution", value: res)
                            }
                            if let codec = version.technical.videoCodec {
                                InfoRow(label: "Video", value: codec.uppercased())
                            }
                            if let audio = version.technical.audioCodec {
                                let channels = version.technical.audioChannels.map { " \($0)ch" } ?? ""
                                InfoRow(label: "Audio", value: audio.uppercased() + channels)
                            }
                            if let hdr = version.technical.hdrFormat {
                                InfoRow(label: "HDR", value: hdr)
                            }
                            if let container = version.technical.container {
                                InfoRow(label: "Container", value: container.uppercased())
                            }
                            if let bitrate = version.technical.bitrate {
                                InfoRow(label: "Bitrate", value: "\(bitrate / 1000) Mbps")
                            }
                            if let size = version.technical.fileSizeMB {
                                let gb = size / 1024
                                let sizeStr = gb >= 1 ? String(format: "%.1f GB", gb) : String(format: "%.0f MB", size)
                                InfoRow(label: "File Size", value: sizeStr)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Collections (from Plex) - if any
            if !vm.collections.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s12) {
                    Text("Collections")
                        .font(.flixor(.title3, weight: .semibold))
                        .foregroundStyle(.white)

                    FlowLayout(spacing: 8) {
                        ForEach(vm.collections, id: \.self) { collection in
                            Text(collection)
                                .font(.flixor(.callout, weight: .medium))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.horizontal, DS.Space.s14)
                                .padding(.vertical, DS.Space.s8)
                                .background(
                                    RoundedRectangle(cornerRadius: DS.Radius.r8, style: .continuous)
                                        .fill(Color.white.opacity(0.1))
                                )
                        }
                    }
                }
            }

            // External Links: IMDb and TMDB, plus the pages MyBluray knows
            // (Letterboxd, Rotten Tomatoes, Apple TV, JustWatch).
            let links = DetailsExternalLink.links(for: vm)
            if !links.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s12) {
                    Text("External Links")
                        .font(.flixor(.title3, weight: .semibold))
                        .foregroundStyle(.white)

                    FlowLayout(spacing: DS.Space.controlGap) {
                        ForEach(links) { link in
                            DetailsExternalLinkButton(link: link)
                        }
                    }
                }
            }
        }
    }

    private func formattedRuntime(_ minutes: Int) -> String {
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            if mins == 0 { return String(localized: "\(hours) hr") }
            return String(localized: "\(hours) hr \(mins) min")
        }
        return String(localized: "\(minutes) min")
    }

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private func formatCurrency(_ amount: Int) -> String {
        Self.currencyFormatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }

    private func languageName(for code: String) -> String {
        let locale = Locale(identifier: "en")
        return locale.localizedString(forLanguageCode: code)?.capitalized ?? code.uppercased()
    }

    // Input format: "2026-01-08" (TMDB format)
    private static let airDateInputFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let airDateOutputFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()

    private func formatAirDate(_ dateString: String) -> String {
        if let date = Self.airDateInputFormatter.date(from: dateString) {
            return Self.airDateOutputFormatter.string(from: date)
        }
        return dateString // Return as-is if parsing fails
    }
}

// MARK: - External links

struct DetailsExternalLink: Identifiable {
    enum Mark { case asset(String, template: Bool, color: Color?), symbol(String, Color) }
    let id: String
    let title: String
    let mark: Mark
    let url: URL

    @MainActor
    static func links(for vm: DetailsViewModel) -> [DetailsExternalLink] {
        var links: [DetailsExternalLink] = []
        func add(_ id: String, _ title: String, _ mark: Mark, _ raw: String?) {
            guard let raw, let url = URL(string: raw), !links.contains(where: { $0.id == id }) else { return }
            links.append(DetailsExternalLink(id: id, title: title, mark: mark, url: url))
        }
        if let imdb = vm.imdbId { add("imdb", "IMDb", .asset("imdb", template: false, color: nil), "https://www.imdb.com/title/\(imdb)/") }
        if let tmdb = vm.tmdbId {
            add("tmdb", "TMDB", .asset("tmdb", template: true, color: Color(hex: "01B4E4")),
                "https://www.themoviedb.org/\(vm.mediaKind == "tv" ? "tv" : "movie")/\(tmdb)")
        }
        let title = vm.myblurayTitle
        let sources = Dictionary((title?.sources ?? []).compactMap { s in s.sourceUrl.map { (s.provider, $0) } },
                                 uniquingKeysWith: { a, _ in a })
        add("letterboxd", "Letterboxd", .asset("letterboxd", template: false, color: nil), sources["letterboxd"])
        let rt = title?.ratings.first(where: { $0.provider == "rotten-tomatoes" && $0.websiteUrl != nil })?.websiteUrl
        add("rt", "Rotten Tomatoes", .asset("tomato-fresh", template: false, color: nil), rt)
        add("appletv", "Apple TV", .symbol("appletv.fill", .white), sources["apple-tv"])
        add("justwatch", "JustWatch", .symbol("play.rectangle.fill", Color(hex: "FFD400")), sources["justwatch"])
        return links
    }
}

/// Grey capsule with the service's mark, like the person page's link buttons.
private struct DetailsExternalLinkButton: View {
    let link: DetailsExternalLink

    @Environment(\.flixorTheme) private var theme
    @Environment(\.openURL) private var openURL
    @State private var hovering = false

    var body: some View {
        Button { openURL(link.url) } label: {
            HStack(spacing: DS.Space.s8) {
                mark
                Text(link.title)
                    .flixorFont(.callout, weight: .semibold)
                    .foregroundStyle(theme.textPrimary)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.textTertiary)
            }
            .padding(.horizontal, DS.Space.s14)
            .frame(height: 36)
            .background(Capsule().fill(hovering ? theme.pressedFill : theme.hoverFill))
            .overlay(Capsule().strokeBorder(theme.separator, lineWidth: DS.Border.thin))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(link.url.absoluteString)
        .accessibilityLabel("Open \(link.title)")
    }

    @ViewBuilder private var mark: some View {
        switch link.mark {
        case .asset(let name, let template, let color):
            if template {
                Image(name).renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                    .frame(height: 12).foregroundStyle(color ?? theme.textPrimary)
            } else {
                Image(name).resizable().aspectRatio(contentMode: .fit)
                    .frame(height: name == "letterboxd" ? 9 : 16)
            }
        case .symbol(let symbol, let color):
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
        }
    }
}

// MARK: - Production Company / Network Logos

/// Logos (or names) of production companies or TV networks. Each one opens
/// the company/network browse page.
private struct DetailsEntityLogoRow: View {
    let title: LocalizedStringKey
    let kind: EntityBrowseRoute.Kind
    let entities: [DetailsViewModel.ProductionCompany]
    let onTap: (EntityBrowseRoute) -> Void

    @Environment(\.flixorTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.itemGap) {
            Text(title)
                .font(.flixor(.title3, weight: .semibold))
                .foregroundStyle(theme.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: DS.Space.itemGap) {
                    ForEach(entities) { entity in
                        DetailsEntityLogoButton(entity: entity) {
                            onTap(EntityBrowseRoute(
                                kind: kind,
                                id: entity.id,
                                name: entity.name,
                                logoPath: Self.tmdbPath(from: entity.logoURL)
                            ))
                        }
                    }
                }
                .padding(.vertical, DS.Space.s4)
            }
        }
    }

    /// TMDB image path ("/abc.png") from a full TMDB image URL
    /// ("https://image.tmdb.org/t/p/w185/abc.png"), matching TMDB's `logo_path`.
    static func tmdbPath(from url: URL?) -> String? {
        guard let url, url.host?.contains("tmdb.org") == true else { return nil }
        let parts = url.path.split(separator: "/")
        // ["t", "p", "<size>", "<file>"...]
        guard parts.count >= 4, parts[0] == "t", parts[1] == "p" else { return nil }
        return "/" + parts.dropFirst(3).joined(separator: "/")
    }
}

private struct DetailsEntityLogoButton: View {
    let entity: DetailsViewModel.ProductionCompany
    let action: () -> Void

    @Environment(\.flixorTheme) private var theme
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Group {
                if let logoURL = entity.logoURL {
                    // TMDB logos are made for white backgrounds (mostly dark on
                    // transparent): grey and inverted, they read as light marks
                    // on the dark tile.
                    CachedAsyncImage(url: logoURL, aspectRatio: nil, contentMode: .fit)
                        .grayscale(1)
                        .colorInvert()
                        .frame(width: 88, height: 30)
                } else {
                    Text(entity.name)
                        .font(.flixor(.callout, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(width: 88, height: 30)
                }
            }
            .padding(.horizontal, DS.Space.s14)
            .padding(.vertical, DS.Space.s12)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.compactCard, style: .continuous)
                    .fill(Color.white.opacity(isHovered ? 0.12 : 0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.compactCard, style: .continuous)
                    .strokeBorder(theme.focusRing, lineWidth: isHovered ? DS.Border.focus : 0)
            )
            .scaleEffect(isHovered ? 1.03 : 1)
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.compactCard, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DS.Motion.quick) { isHovered = hovering }
        }
        .help("Browse \(entity.name)")
        .accessibilityLabel(Text("Browse titles from \(entity.name)"))
    }
}

// MARK: - Info Row Component
private struct InfoRow: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            Text(label)
                .font(.flixor(.callout, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .font(.flixor(.body))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}

// MARK: - Flow Layout for Tags/Collections
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
                self.size.width = max(self.size.width, x)
            }
            self.size.height = y + rowHeight
        }
    }
}

// MARK: - Info Column Component
private struct InfoColumn: View {
    let title: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s8) {
            Text(title)
                .font(.flixor(.callout, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .textCase(.uppercase)

            Text(content)
                .font(.flixor(.bodyLarge))
                .lineSpacing(3)
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
