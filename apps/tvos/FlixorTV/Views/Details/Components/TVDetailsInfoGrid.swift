import SwiftUI
import FlixorKit

struct TVDetailsInfoGrid: View {
    @ObservedObject var vm: TVDetailsViewModel
    var focusNS: Namespace.ID
    var onFocusChange: ((Bool) -> Void)?
    @EnvironmentObject private var profileSettings: TVProfileSettings
    @State private var isFocused: Bool = false
    @State private var selectedModal: DetailsSectionModalType?
    @State private var lastFocusedSection: FocusableDetailsSection = .about
    @FocusState private var focusedSection: FocusableDetailsSection?

    private enum FocusableDetailsSection: Hashable {
        case about
        case cast
        case production
        case networks
        case information
        case languages
        case technical
    }

    private enum DetailsSectionModalType: Identifiable {
        case about
        case cast
        case production
        case networks
        case information
        case languages
        case technical

        var id: String {
            switch self {
            case .about: return "about"
            case .cast: return "cast"
            case .production: return "production"
            case .networks: return "networks"
            case .information: return "information"
            case .languages: return "languages"
            case .technical: return "technical"
            }
        }
    }

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

            if profileSettings.showCastCrew && !castAndCrew.isEmpty {
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
        .onChange(of: focusedSection) { newValue in
            guard let newValue else { return }
            lastFocusedSection = newValue
            if !isFocused {
                isFocused = true
            }
            onFocusChange?(true)
        }
        .fullScreenCover(item: $selectedModal) { modalType in
            if let payload = modalPayload(for: modalType) {
                TVDetailsSectionModal(payload: payload) {
                    closeModal()
                }
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
                Button(action: { openModal(.about) }) {
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
                                .lineLimit(4)
                        }

                        HStack {
                            Spacer()
                            Text("MORE")
                                .font(.system(size: 18, weight: .heavy))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        sectionCardBackground(
                            cornerRadius: 16,
                            isFocused: focusedSection == .about
                        )
                    )
                    .shadow(color: .black.opacity(focusedSection == .about ? 0.55 : 0.14), radius: focusedSection == .about ? 24 : 8, y: focusedSection == .about ? 14 : 4)
                    .scaleEffect(focusedSection == .about ? 1.02 : 1.0)
                    .animation(.easeOut(duration: 0.2), value: focusedSection)
                }
                .buttonStyle(NoHighlightButtonStyle())
                .focused($focusedSection, equals: .about)
                .prefersDefaultFocus(true, in: focusNS)

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
    }

    private var castSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(vm.isEpisode && !vm.guestStars.isEmpty ? "Guest Stars" : "Cast & Crew")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.white)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(castAndCrew.prefix(12)) { person in
                        CastCrewCard(person: person, onFocusChange: { focused in
                            if focused && !isFocused {
                                isFocused = true
                                onFocusChange?(true)
                            }
                        })
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func companySection(title: String, items: [TVDetailsViewModel.ProductionCompany]) -> some View {
        Button(action: {
            if title == "Networks" {
                openModal(.networks)
            } else {
                openModal(.production)
            }
        }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(title)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("MORE")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.9))
                }

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
                        }
                    }
                }
            }
            .padding(14)
            .background(
                sectionCardBackground(
                    cornerRadius: 16,
                    isFocused: title == "Networks" ? focusedSection == .networks : focusedSection == .production
                )
            )
            .shadow(
                color: .black.opacity((title == "Networks" ? focusedSection == .networks : focusedSection == .production) ? 0.55 : 0.14),
                radius: (title == "Networks" ? focusedSection == .networks : focusedSection == .production) ? 24 : 8,
                y: (title == "Networks" ? focusedSection == .networks : focusedSection == .production) ? 14 : 4
            )
            .scaleEffect((title == "Networks" ? focusedSection == .networks : focusedSection == .production) ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.2), value: focusedSection)
        }
        .buttonStyle(NoHighlightButtonStyle())
        .focused($focusedSection, equals: title == "Networks" ? .networks : .production)
    }

    private var columnsSection: some View {
        HStack(alignment: .top, spacing: 46) {
            informationColumn
                .frame(maxWidth: .infinity, alignment: .leading)
            languagesColumn
                .frame(maxWidth: .infinity, alignment: .leading)
            technicalColumn
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var informationColumn: some View {
        Button(action: { openModal(.information) }) {
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

                HStack {
                    Spacer()
                    Text("MORE")
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding(18)
            .background(
                sectionCardBackground(
                    cornerRadius: 14,
                    isFocused: focusedSection == .information
                )
            )
            .shadow(color: .black.opacity(focusedSection == .information ? 0.55 : 0.14), radius: focusedSection == .information ? 24 : 8, y: focusedSection == .information ? 14 : 4)
            .scaleEffect(focusedSection == .information ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.2), value: focusedSection)
        }
        .buttonStyle(NoHighlightButtonStyle())
        .focused($focusedSection, equals: .information)
    }

    private var languagesColumn: some View {
        Button(action: { openModal(.languages) }) {
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

                HStack {
                    Spacer()
                    Text("MORE")
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding(18)
            .background(
                sectionCardBackground(
                    cornerRadius: 14,
                    isFocused: focusedSection == .languages
                )
            )
            .shadow(color: .black.opacity(focusedSection == .languages ? 0.55 : 0.14), radius: focusedSection == .languages ? 24 : 8, y: focusedSection == .languages ? 14 : 4)
            .scaleEffect(focusedSection == .languages ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.2), value: focusedSection)
        }
        .buttonStyle(NoHighlightButtonStyle())
        .focused($focusedSection, equals: .languages)
    }

    private var technicalColumn: some View {
        Button(action: { openModal(.technical) }) {
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

                HStack {
                    Spacer()
                    Text("MORE")
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding(18)
            .background(
                sectionCardBackground(
                    cornerRadius: 14,
                    isFocused: focusedSection == .technical
                )
            )
            .shadow(color: .black.opacity(focusedSection == .technical ? 0.55 : 0.14), radius: focusedSection == .technical ? 24 : 8, y: focusedSection == .technical ? 14 : 4)
            .scaleEffect(focusedSection == .technical ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.2), value: focusedSection)
        }
        .buttonStyle(NoHighlightButtonStyle())
        .focused($focusedSection, equals: .technical)
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

                if vm.overseerrStatus != .notConfigured {
                    Button {
                        Task { await vm.requestInOverseerr() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: vm.overseerrStatus.canRequest ? "paperplane.fill" : "checkmark.seal.fill")
                                .font(.system(size: 14, weight: .semibold))
                            Text(overseerrButtonLabel)
                                .font(.system(size: 15, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(vm.overseerrStatus.canRequest ? Color(red: 0.12, green: 0.42, blue: 0.34) : Color.white.opacity(0.16))
                        )
                    }
                    .buttonStyle(NoHighlightButtonStyle())
                    .disabled(!vm.overseerrStatus.canRequest || vm.isSubmittingOverseerrRequest)
                }

                if profileSettings.traktSyncRatings,
                   FlixorCore.shared.isTraktAuthenticated,
                   let suggested = vm.suggestedTraktRating {
                    Button {
                        Task { _ = await vm.submitTraktRating(suggested) }
                    } label: {
                        HStack(spacing: 8) {
                            Image("trakt")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 18, height: 18)
                            Text(vm.traktRatingValue != nil ? "Rated \(vm.traktRatingValue!)/10 on Trakt" : "Rate \(suggested)/10 on Trakt")
                                .font(.system(size: 15, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(red: 0.16, green: 0.12, blue: 0.22))
                        )
                    }
                    .buttonStyle(NoHighlightButtonStyle())
                }
            }

            if let message = vm.overseerrRequestMessage, !message.isEmpty {
                Text(message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.74))
            }
        }
    }

    private var overseerrButtonLabel: String {
        if vm.isSubmittingOverseerrRequest {
            return "Requesting..."
        }
        if vm.overseerrStatus.canRequest {
            return "Request in Overseerr"
        }
        switch vm.overseerrStatus.status {
        case .available:
            return "Available"
        case .pending:
            return "Request Pending"
        case .approved:
            return "Request Approved"
        case .processing:
            return "Processing"
        case .partiallyAvailable:
            return "Partially Available"
        case .declined:
            return "Declined"
        case .notRequested:
            return "Not Requested"
        case .unknown:
            return "Overseerr Status"
        }
    }

    private func openModal(_ type: DetailsSectionModalType) {
        selectedModal = type
    }

    private func closeModal() {
        selectedModal = nil
        let returnFocus = lastFocusedSection
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            focusedSection = returnFocus
        }
    }

    private func modalPayload(for type: DetailsSectionModalType) -> TVDetailsSectionModal.Payload? {
        switch type {
        case .about:
            var blocks: [TVDetailsSectionModal.Payload.Block] = []
            if !vm.title.isEmpty {
                blocks.append(.init(title: "Title", value: vm.title))
            }
            if !vm.genres.isEmpty {
                blocks.append(.init(title: "Genres", value: vm.genres.joined(separator: ", ")))
            }
            if let tagline = vm.tagline, !tagline.isEmpty {
                blocks.append(.init(title: "Tagline", value: tagline))
            }
            if let rating = vm.rating, !rating.isEmpty {
                blocks.append(.init(title: "Content Rating", value: rating))
            }
            if !vm.overview.isEmpty {
                blocks.append(.init(title: "Synopsis", value: vm.overview))
            }
            return TVDetailsSectionModal.Payload(
                title: "About",
                subtitle: vm.title,
                blocks: blocks
            )
        case .cast:
            let castLines = castAndCrew.map { person in
                if let role = person.role, !role.isEmpty {
                    return "\(person.name) — \(role)"
                }
                return person.name
            }.joined(separator: "\n")
            return TVDetailsSectionModal.Payload(
                title: vm.isEpisode && !vm.guestStars.isEmpty ? "Guest Stars & Crew" : "Cast & Crew",
                subtitle: vm.title,
                blocks: [
                    .init(title: "People", value: castLines.isEmpty ? "Not available" : castLines)
                ]
            )
        case .production:
            let value = vm.productionCompanies.map(\.name).joined(separator: "\n")
            return TVDetailsSectionModal.Payload(
                title: "Production",
                subtitle: vm.title,
                blocks: [
                    .init(title: "Companies", value: value.isEmpty ? "Not available" : value)
                ]
            )
        case .networks:
            let value = vm.networks.map(\.name).joined(separator: "\n")
            return TVDetailsSectionModal.Payload(
                title: "Networks",
                subtitle: vm.title,
                blocks: [
                    .init(title: "Networks", value: value.isEmpty ? "Not available" : value)
                ]
            )
        case .information:
            var lines: [String] = []
            if let year = vm.year { lines.append("Released: \(year)") }
            if let runtime = vm.runtime { lines.append("Run Time: \(formattedRuntime(runtime))") }
            if let rating = vm.rating { lines.append("Rated: \(rating)") }
            if let status = vm.status, !status.isEmpty, !vm.isEpisode { lines.append("Status: \(status)") }
            if vm.mediaKind == "tv", !vm.isEpisode {
                if let seasons = vm.numberOfSeasons { lines.append("Seasons: \(seasons)") }
                if let episodes = vm.numberOfEpisodes { lines.append("Episodes: \(episodes)") }
            }
            if vm.mediaKind == "movie" {
                if let budget = vm.budget { lines.append("Budget: \(formatCurrency(budget))") }
                if let revenue = vm.revenue { lines.append("Box Office: \(formatCurrency(revenue))") }
            }
            if let studio = vm.studio, !studio.isEmpty { lines.append("Studio: \(studio)") }
            if !vm.creators.isEmpty && vm.mediaKind == "tv" { lines.append("Created By: \(vm.creators.joined(separator: ", "))") }
            if !vm.directors.isEmpty { lines.append("\(vm.directors.count > 1 ? "Directors" : "Director"): \(vm.directors.joined(separator: ", "))") }
            if !vm.writers.isEmpty { lines.append("\(vm.writers.count > 1 ? "Writers" : "Writer"): \(vm.writers.joined(separator: ", "))") }
            if vm.isEpisode {
                if let showTitle = vm.showTitle, !showTitle.isEmpty { lines.append("Show: \(showTitle)") }
                if let season = vm.seasonNumber, let episode = vm.episodeNumber {
                    lines.append("Episode: Season \(season), Episode \(episode)")
                }
                if let airDate = vm.airDate, !airDate.isEmpty { lines.append("Air Date: \(formatAirDate(airDate))") }
                if let director = vm.episodeDirector, !director.isEmpty { lines.append("Directed By: \(director)") }
                if let writer = vm.episodeWriter, !writer.isEmpty { lines.append("Written By: \(writer)") }
            }
            return TVDetailsSectionModal.Payload(
                title: "Information",
                subtitle: vm.title,
                blocks: [
                    .init(title: "Details", value: lines.joined(separator: "\n"))
                ]
            )
        case .languages:
            let original = (vm.originalLanguage?.isEmpty == false) ? languageName(for: vm.originalLanguage ?? "") : "Not available"
            let audio = vm.audioTracks.map(\.name).joined(separator: ", ")
            let subtitles = vm.subtitleTracks.map(\.name).joined(separator: ", ")
            return TVDetailsSectionModal.Payload(
                title: "Languages",
                subtitle: vm.title,
                blocks: [
                    .init(title: "Original Audio", value: original),
                    .init(title: "Audio", value: audio.isEmpty ? "Not available" : audio),
                    .init(title: "Subtitles", value: subtitles.isEmpty ? "Not available" : subtitles)
                ]
            )
        case .technical:
            var lines: [String] = []
            if let version = vm.activeVersionDetail {
                if let resolution = version.technical.resolution { lines.append("Resolution: \(resolution)") }
                if let video = version.technical.videoCodec { lines.append("Video: \(video.uppercased())") }
                if let audio = version.technical.audioCodec {
                    let channels = version.technical.audioChannels.map { " \($0)ch" } ?? ""
                    lines.append("Audio: \(audio.uppercased())\(channels)")
                }
                if let hdr = hdrLabel(for: version.technical.videoProfile) { lines.append("HDR: \(hdr)") }
                if let bitrate = version.technical.bitrate { lines.append("Bitrate: \(bitrate / 1000) Mbps") }
                if let fileSizeMB = version.technical.fileSizeMB { lines.append("File Size: \(fileSize(fileSizeMB))") }
                if let container = version.technical.container { lines.append("Container: \(container.uppercased())") }
            }
            if !vm.badges.isEmpty {
                lines.append("Badges: \(vm.badges.joined(separator: ", "))")
            }
            return TVDetailsSectionModal.Payload(
                title: "Technical",
                subtitle: vm.title,
                blocks: [
                    .init(title: "Media Info", value: lines.isEmpty ? "Not available" : lines.joined(separator: "\n"))
                ]
            )
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

    private func sectionCardBackground(cornerRadius: CGFloat, isFocused: Bool) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(isFocused ? 0.08 : 0.05))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(isFocused ? 0.85 : 0.12), lineWidth: isFocused ? 3 : 1)
            )
    }
}

private struct PersonCardModel: Identifiable {
    let id: String
    let name: String
    let role: String?
    let image: URL?
}

private struct CastCrewCard: View {
    let person: PersonCardModel
    var onFocusChange: ((Bool) -> Void)?
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: {}) {
            VStack(spacing: 10) {
                Group {
                    if let image = person.image {
                        CachedAsyncImage(url: image, contentMode: .fill) {
                            Circle().fill(Color.white.opacity(0.1))
                        }
                    } else {
                        Circle().fill(Color.white.opacity(0.15))
                            .overlay(
                                Text(initials)
                                    .font(.system(size: 32, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.6))
                            )
                    }
                }
                .frame(width: 110, height: 110)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(isFocused ? 0.88 : 0.12), lineWidth: isFocused ? 3 : 1)
                )
                .shadow(color: Color.white.opacity(isFocused ? 0.22 : 0.0), radius: isFocused ? 10 : 0, y: 0)

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
        }
        .buttonStyle(NoHighlightButtonStyle())
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.08 : 1.0)
        .shadow(color: .black.opacity(isFocused ? 0.5 : 0.1), radius: isFocused ? 16 : 4, y: isFocused ? 10 : 2)
        .animation(.easeOut(duration: 0.18), value: isFocused)
        .onChange(of: isFocused) { newValue in
            if newValue {
                onFocusChange?(true)
            }
        }
    }

    private var initials: String {
        let parts = person.name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(person.name.prefix(2)).uppercased()
    }
}

private struct NoHighlightButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

private struct TVDetailsSectionModal: View {
    struct Payload {
        struct Block: Identifiable {
            let id = UUID()
            let title: String
            let value: String
        }

        let title: String
        let subtitle: String?
        let blocks: [Block]
    }

    let payload: Payload
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.58)
                .ignoresSafeArea()

            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.white.opacity(0.28), lineWidth: 1)
                )
                .frame(width: 980, height: 760)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(payload.title)
                                    .font(.system(size: 42, weight: .bold))
                                    .foregroundStyle(.white)
                                if let subtitle = payload.subtitle, !subtitle.isEmpty {
                                    Text(subtitle)
                                        .font(.system(size: 22, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.72))
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Button(action: onClose) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 48, height: 48)
                                    .background(Circle().fill(Color.white.opacity(0.18)))
                            }
                            .buttonStyle(.card)
                        }

                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 22) {
                                ForEach(payload.blocks) { block in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(block.title)
                                            .font(.system(size: 30, weight: .bold))
                                            .foregroundStyle(.white)
                                        Text(block.value)
                                            .font(.system(size: 30, weight: .regular))
                                            .foregroundStyle(.white.opacity(0.9))
                                            .lineSpacing(6)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .padding(.bottom, 12)
                        }
                    }
                    .padding(.horizontal, 42)
                    .padding(.vertical, 32)
                }
        }
        .transition(.opacity)
        .onExitCommand {
            onClose()
        }
    }
}
