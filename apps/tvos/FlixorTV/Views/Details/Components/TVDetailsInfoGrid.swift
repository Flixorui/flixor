import SwiftUI
import FlixorKit

struct TVDetailsInfoGrid: View {
    @ObservedObject var vm: TVDetailsViewModel
    var focusNS: Namespace.ID
    var onFocusChange: ((Bool) -> Void)?
    @State private var isFocused: Bool = false

    private var castAndCrew: [PersonCardModel] {
        var people: [PersonCardModel] = []
        if vm.isEpisode && !vm.guestStars.isEmpty {
            people.append(contentsOf: vm.guestStars.prefix(12).map {
                PersonCardModel(id: $0.id, name: $0.name, role: $0.role, image: $0.profile)
            })
        } else {
            people.append(contentsOf: vm.cast.prefix(12).map {
                PersonCardModel(id: $0.id, name: $0.name, role: $0.role, image: $0.profile)
            })
        }
        people.append(contentsOf: vm.crew.prefix(6).map {
            PersonCardModel(id: $0.id, name: $0.name, role: $0.job, image: $0.profile)
        })
        var seen = Set<String>()
        return people.filter { seen.insert("\($0.id)-\($0.name)").inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 44) {
            aboutSection

            if !castAndCrew.isEmpty {
                castSection
            }

            if vm.mediaKind == "movie" && !vm.productionCompanies.isEmpty {
                companySection(title: "Production", items: vm.productionCompanies)
            }

            if vm.mediaKind == "tv" && !vm.networks.isEmpty {
                companySection(title: "Networks", items: vm.networks)
            }

            columnsSection

            if !vm.collections.isEmpty {
                collectionsSection
            }

            externalLinksSection
        }
        .padding(.horizontal, 80)
        .padding(.bottom, 80)
        .onChange(of: isFocused) { newValue in
            // Only report when gaining focus
            if newValue {
                onFocusChange?(true)
            }
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("About")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)

            if let tagline = vm.tagline, !tagline.isEmpty {
                Text("\"\(tagline)\"")
                    .font(.system(size: 22, weight: .regular))
                    .italic()
                    .foregroundStyle(.white.opacity(0.7))
            }

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(vm.title)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)

                    if !vm.genres.isEmpty {
                        Text(vm.genres.joined(separator: ", ").uppercased())
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.62))
                    }

                    if !vm.overview.isEmpty {
                        Text(vm.overview)
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(.white.opacity(0.86))
                            .lineSpacing(4)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.08)))

                if let rating = vm.rating, !rating.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                                .font(.system(size: 22))
                            Text(rating)
                                .font(.system(size: 34, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        Text("CONTENT RATING")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .padding(20)
                    .frame(width: 260, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.08)))
                }
            }
        }
        .focusable(true) { focused in
            if focused && !isFocused {
                isFocused = true
            }
        }
        .prefersDefaultFocus(true, in: focusNS)
    }

    private var castSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(vm.isEpisode && !vm.guestStars.isEmpty ? "Guest Stars" : "Cast & Crew")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.white)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(castAndCrew) { person in
                        VStack(spacing: 10) {
                            Group {
                                if let image = person.image {
                                    CachedAsyncImage(url: image, contentMode: .fill) {
                                        Circle().fill(Color.white.opacity(0.1))
                                    }
                                } else {
                                    Circle().fill(Color.white.opacity(0.1))
                                }
                            }
                            .frame(width: 110, height: 110)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))

                            Text(person.name)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            if let role = person.role, !role.isEmpty {
                                Text(role)
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(.white.opacity(0.65))
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: 130)
                        .focusable(true) { focused in
                            if focused && !isFocused {
                                isFocused = true
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func companySection(title: String, items: [TVDetailsViewModel.ProductionCompany]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items.prefix(8)) { item in
                        Group {
                            if let logo = item.logoURL {
                                CachedAsyncImage(url: logo, contentMode: .fit) {
                                    Text(item.name)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 12)
                                }
                                .frame(width: 110, height: 38)
                            } else {
                                Text(item.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.black)
                                    .lineLimit(1)
                                    .padding(.horizontal, 14)
                                    .frame(height: 38)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white))
                        .focusable(true) { focused in
                            if focused && !isFocused {
                                isFocused = true
                            }
                        }
                    }
                }
            }
        }
    }

    private var columnsSection: some View {
        HStack(alignment: .top, spacing: 46) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Information")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 14) {
                    if let year = vm.year { infoRow("Released", year) }
                    if let runtime = vm.runtime { infoRow("Run Time", formattedRuntime(runtime)) }
                    if let rating = vm.rating { infoRow("Rated", rating) }
                    if let status = vm.status, !status.isEmpty, !vm.isEpisode { infoRow("Status", status) }
                    if vm.mediaKind == "tv", !vm.isEpisode {
                        if let seasons = vm.numberOfSeasons { infoRow("Seasons", "\(seasons)") }
                        if let episodes = vm.numberOfEpisodes { infoRow("Episodes", "\(episodes)") }
                    }
                    if vm.mediaKind == "movie" {
                        if let budget = vm.budget { infoRow("Budget", formatCurrency(budget)) }
                        if let revenue = vm.revenue { infoRow("Box Office", formatCurrency(revenue)) }
                    }
                    if let studio = vm.studio, !studio.isEmpty { infoRow("Studio", studio) }
                    if !vm.creators.isEmpty && vm.mediaKind == "tv" { infoRow("Created By", vm.creators.joined(separator: ", ")) }
                    if !vm.directors.isEmpty { infoRow(vm.directors.count > 1 ? "Directors" : "Director", vm.directors.joined(separator: ", ")) }
                    if !vm.writers.isEmpty { infoRow(vm.writers.count > 1 ? "Writers" : "Writer", vm.writers.joined(separator: ", ")) }
                    if vm.isEpisode {
                        if let showTitle = vm.showTitle, !showTitle.isEmpty { infoRow("Show", showTitle) }
                        if let season = vm.seasonNumber, let episode = vm.episodeNumber {
                            infoRow("Episode", "Season \(season), Episode \(episode)")
                        }
                        if let airDate = vm.airDate, !airDate.isEmpty { infoRow("Air Date", formatAirDate(airDate)) }
                        if let director = vm.episodeDirector, !director.isEmpty { infoRow("Directed By", director) }
                        if let writer = vm.episodeWriter, !writer.isEmpty { infoRow("Written By", writer) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 18) {
                Text("Languages")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 14) {
                    if let original = vm.originalLanguage, !original.isEmpty {
                        infoRow("Original Audio", languageName(for: original))
                    }
                    if !vm.audioTracks.isEmpty {
                        infoRow("Audio", vm.audioTracks.map { $0.name }.joined(separator: ", "))
                    }
                    if !vm.subtitleTracks.isEmpty {
                        infoRow("Subtitles", vm.subtitleTracks.map { $0.name }.joined(separator: ", "))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 18) {
                Text("Technical")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 14) {
                    if let version = vm.activeVersionDetail {
                        if let resolution = version.technical.resolution { infoRow("Resolution", resolution) }
                        if let video = version.technical.videoCodec { infoRow("Video", video.uppercased()) }
                        if let audio = version.technical.audioCodec {
                            let channels = version.technical.audioChannels.map { " \($0)ch" } ?? ""
                            infoRow("Audio", audio.uppercased() + channels)
                        }
                        if let hdr = hdrLabel(for: version.technical.videoProfile) { infoRow("HDR", hdr) }
                        if let bitrate = version.technical.bitrate { infoRow("Bitrate", "\(bitrate / 1000) Mbps") }
                        if let fileSizeMB = version.technical.fileSizeMB { infoRow("File Size", fileSize(fileSizeMB)) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .focusable(true) { focused in
            if focused && !isFocused {
                isFocused = true
            }
        }
    }

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Collections")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(vm.collections, id: \.self) { collection in
                    Text(collection)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.1)))
                }
            }
        }
        .focusable(true) { focused in
            if focused && !isFocused {
                isFocused = true
            }
        }
    }

    private var externalLinksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("External Links")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)

            HStack(spacing: 12) {
                if let imdbId = vm.imdbId,
                   let url = URL(string: "https://www.imdb.com/title/\(imdbId)") {
                    Link(destination: url) {
                        HStack(spacing: 8) {
                            Image("imdb")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 18)
                            Text("View on IMDb")
                                .font(.system(size: 15, weight: .medium))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(red: 0.96, green: 0.77, blue: 0.09)))
                    }
                }

                if let tmdbId = vm.tmdbId,
                   let url = URL(string: "https://www.themoviedb.org/\(vm.mediaKind == "tv" ? "tv" : "movie")/\(tmdbId)") {
                    Link(destination: url) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(red: 0.02, green: 0.82, blue: 0.61))
                                .frame(width: 18, height: 18)
                                .overlay(Text("T").font(.system(size: 11, weight: .bold)).foregroundStyle(.white))
                            Text("View on TMDB")
                                .font(.system(size: 15, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(red: 0.03, green: 0.21, blue: 0.33)))
                    }
                }
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
            Text(value)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(4)
        }
    }

    private func formattedRuntime(_ minutes: Int) -> String {
        if minutes >= 60 {
            let hours = minutes / 60
            let remainder = minutes % 60
            if remainder == 0 { return "\(hours) hr" }
            return "\(hours) hr \(remainder) min"
        }
        return "\(minutes) min"
    }

    private func fileSize(_ megabytes: Double) -> String {
        if megabytes >= 1024 {
            return String(format: "%.1f GB", megabytes / 1024)
        }
        return String(format: "%.0f MB", megabytes)
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
        let input = DateFormatter()
        input.dateFormat = "yyyy-MM-dd"
        let output = DateFormatter()
        output.dateStyle = .long
        guard let date = input.date(from: dateString) else { return dateString }
        return output.string(from: date)
    }

    private func hdrLabel(for profile: String?) -> String? {
        let value = (profile ?? "").lowercased()
        if value.contains("dolby") || value.contains("dv") { return "Dolby Vision" }
        if value.contains("hdr10+") { return "HDR10+" }
        if value.contains("hdr10") { return "HDR10" }
        if value.contains("hdr") { return "HDR" }
        return nil
    }
}

private struct PersonCardModel: Identifiable {
    let id: String
    let name: String
    let role: String?
    let image: URL?
}
