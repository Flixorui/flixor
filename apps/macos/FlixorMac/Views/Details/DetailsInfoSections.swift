//
//  DetailsInfoSections.swift
//  FlixorMac
//
//  Details tab: cast & crew, about, info, technical details, collections
//

import SwiftUI
import FlixorKit

struct DetailsTabContent: View {
    @ObservedObject var vm: DetailsViewModel
    let layout: DetailsLayoutMetrics
    var onPersonTap: (CastCrewCard.Person) -> Void

    @ObservedObject private var profileSettings = ProfileSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            // About Section (Apple TV+ style cards) - moved above Cast & Crew
            VStack(alignment: .leading, spacing: 16) {
                Text("About")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)

                // Tagline (if available)
                if let tagline = vm.tagline, !tagline.isEmpty {
                    Text("\"\(tagline)\"")
                        .font(.system(size: 15, weight: .regular))
                        .italic()
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.bottom, 4)
                }

                HStack(alignment: .top, spacing: 16) {
                    // Main info card
                    VStack(alignment: .leading, spacing: 12) {
                        Text(vm.title)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)

                        if !vm.genres.isEmpty {
                            Text(vm.genres.joined(separator: ", ").uppercased())
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))
                        }

                        if !vm.overview.isEmpty {
                            Text(vm.overview)
                                .font(.system(size: 14))
                                .lineSpacing(4)
                                .foregroundStyle(.white.opacity(0.85))
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )

                    // Content rating card - height matches description card
                    if let rating = vm.rating {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                                    .font(.system(size: 18))
                                Text(rating)
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            Text("CONTENT RATING")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))
                            Spacer(minLength: 0)
                        }
                        .padding(20)
                        .frame(width: 200)
                        .frame(maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            // Cast & Crew Section (Apple TV+ style) - also show for episodes with guest stars
            if profileSettings.showCastCrew && (!vm.cast.isEmpty || !vm.crew.isEmpty || !vm.guestStars.isEmpty) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(vm.isEpisode && !vm.guestStars.isEmpty ? "Guest Stars" : "Cast & Crew")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 20) {
                            ForEach(allCastCrew) { person in
                                CastCrewCircleCard(person: person, onTap: { onPersonTap(person) })
                            }
                        }
                    }
                }
            }
            
            // Production Section (Movies) - with logos
            if vm.mediaKind == "movie" && !vm.productionCompanies.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Production")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(vm.productionCompanies.prefix(6)) { company in
                                if let logoURL = company.logoURL {
                                    CachedAsyncImage(url: logoURL, aspectRatio: nil, contentMode: .fit)
                                        .frame(width: 80, height: 32)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(Color.white)
                                        )
                                } else {
                                    Text(company.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(Color.white)
                                        )
                                }
                            }
                        }
                    }
                }
            }

            // Networks Section (TV) - with logos
            if vm.mediaKind == "tv" && !vm.networks.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Networks")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(vm.networks.prefix(6)) { network in
                                if let logoURL = network.logoURL {
                                    CachedAsyncImage(url: logoURL, aspectRatio: nil, contentMode: .fit)
                                        .frame(width: 80, height: 32)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(Color.white)
                                        )
                                } else {
                                    Text(network.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(Color.white)
                                        )
                                }
                            }
                        }
                    }
                }
            }

            // Three-column info section (Apple TV+ style)
            HStack(alignment: .top, spacing: 40) {
                // Information column
                VStack(alignment: .leading, spacing: 20) {
                    Text("Information")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)

                    VStack(alignment: .leading, spacing: 16) {
                        // Episode-specific info
                        if vm.isEpisode {
                            if let showTitle = vm.showTitle {
                                InfoRow(label: "Show", value: showTitle)
                            }

                            if let sNum = vm.seasonNumber, let eNum = vm.episodeNumber {
                                InfoRow(label: "Episode", value: "Season \(sNum), Episode \(eNum)")
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
                VStack(alignment: .leading, spacing: 20) {
                    Text("Languages")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)

                    VStack(alignment: .leading, spacing: 16) {
                        if let lang = vm.originalLanguage {
                            InfoRow(label: "Original Audio", value: languageName(for: lang))
                        }

                        if !vm.audioTracks.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Audio")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.5))
                                Text(vm.audioTracks.map { $0.name }.joined(separator: ", "))
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .lineLimit(4)
                            }
                        }

                        if !vm.subtitleTracks.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Subtitles")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.5))
                                Text(vm.subtitleTracks.map { $0.name }.joined(separator: ", "))
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .lineLimit(6)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Technical / Production column
                VStack(alignment: .leading, spacing: 20) {
                    Text("Technical")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)

                    VStack(alignment: .leading, spacing: 16) {
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
                VStack(alignment: .leading, spacing: 12) {
                    Text("Collections")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)

                    FlowLayout(spacing: 8) {
                        ForEach(vm.collections, id: \.self) { collection in
                            Text(collection)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.white.opacity(0.1))
                                )
                        }
                    }
                }
            }

            // External Links
            if vm.imdbId != nil || vm.tmdbId != nil {
                VStack(alignment: .leading, spacing: 12) {
                    Text("External Links")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)

                    HStack(spacing: 12) {
                        if let imdbId = vm.imdbId {
                            Link(destination: URL(string: "https://www.imdb.com/title/\(imdbId)")!) {
                                HStack(spacing: 8) {
                                    Image("imdb")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(height: 18)
                                    Text("View on IMDb")
                                        .font(.system(size: 13, weight: .medium))
                                }
                                .foregroundStyle(.black)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color(red: 0.96, green: 0.77, blue: 0.09)) // IMDb yellow
                                )
                            }
                        }
                        if let tmdbId = vm.tmdbId {
                            let mediaPath = vm.mediaKind == "tv" ? "tv" : "movie"
                            Link(destination: URL(string: "https://www.themoviedb.org/\(mediaPath)/\(tmdbId)")!) {
                                HStack(spacing: 8) {
                                    // TMDB logo representation
                                    ZStack {
                                        Circle()
                                            .fill(Color(red: 0.02, green: 0.82, blue: 0.61)) // TMDB teal
                                            .frame(width: 20, height: 20)
                                        Text("T")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                    Text("View on TMDB")
                                        .font(.system(size: 13, weight: .medium))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color(red: 0.03, green: 0.21, blue: 0.33)) // TMDB dark blue
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    // Combine cast and crew for display
    private var allCastCrew: [CastCrewCard.Person] {
        var people: [CastCrewCard.Person] = []

        // For episodes, use guest stars
        if vm.isEpisode && !vm.guestStars.isEmpty {
            for g in vm.guestStars.prefix(12) {
                people.append(CastCrewCard.Person(id: g.id, name: g.name, role: g.role, image: g.profile))
            }
        } else {
            // Add cast (actors) with their character names
            for c in vm.cast.prefix(12) {
                people.append(CastCrewCard.Person(id: c.id, name: c.name, role: c.role, image: c.profile))
            }
        }

        // Add key crew (directors, writers)
        for c in vm.crew.prefix(4) {
            people.append(CastCrewCard.Person(id: c.id, name: c.name, role: c.job, image: c.profile))
        }
        return people
    }

    private func formattedRuntime(_ minutes: Int) -> String {
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            if mins == 0 { return "\(hours) hr" }
            return "\(hours) hr \(mins) min"
        }
        return "\(minutes) min"
    }

    private func formatCurrency(_ amount: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }

    private func languageName(for code: String) -> String {
        let locale = Locale(identifier: "en")
        return locale.localizedString(forLanguageCode: code)?.capitalized ?? code.uppercased()
    }

    private func formatAirDate(_ dateString: String) -> String {
        // Input format: "2026-01-08" (TMDB format)
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd"

        let outputFormatter = DateFormatter()
        outputFormatter.dateStyle = .long
        outputFormatter.timeStyle = .none

        if let date = inputFormatter.date(from: dateString) {
            return outputFormatter.string(from: date)
        }
        return dateString // Return as-is if parsing fails
    }
}

// MARK: - Cast & Crew Circle Card (Apple TV+ style)
private struct CastCrewCircleCard: View {
    let person: CastCrewCard.Person
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                // Circular profile image
                Group {
                    if let imageURL = person.image {
                        CachedAsyncImage(url: imageURL)
                            .scaledToFill()
                    } else {
                        // Initials fallback
                        ZStack {
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                            Text(initials(for: person.name))
                                .font(.system(size: 28, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }
                .frame(width: 100, height: 100)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(isHovered ? 0.4 : 0.15), lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)

                // Name
                Text(person.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                // Role/Character
                if let role = person.role {
                    Text(role)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            .frame(width: 110)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func initials(for name: String) -> String {
        let parts = name.components(separatedBy: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}

// MARK: - Info Row Component
private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .font(.system(size: 14))
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
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .textCase(.uppercase)

            Text(content)
                .font(.system(size: 15))
                .lineSpacing(3)
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
