//
//  DetailsCastAndTechnical.swift
//  FlixorMac
//
//  CastCrewCard (and its Person model) plus cast/technical/production section views
//

import SwiftUI
import FlixorKit

struct CastCrewCard: View, Identifiable {
    struct Person: Identifiable {
        let id: String
        let name: String
        let role: String?
        let image: URL?
    }

    let person: Person
    var onTap: () -> Void
    var id: String { person.id }
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    if let imageURL = person.image {
                        CachedAsyncImage(url: imageURL)
                            .aspectRatio(2/3, contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .aspectRatio(2/3, contentMode: .fit)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.white.opacity(0.25))
                            )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)

                VStack(alignment: .leading, spacing: 3) {
                    Text(person.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                        .foregroundStyle(.white.opacity(0.95))
                    if let role = person.role, !role.isEmpty {
                        Text(role)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.bottom, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.06 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(isHovered ? 0.18 : 0.12), lineWidth: isHovered ? 1 : 0.5)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(color: .black.opacity(isHovered ? 0.35 : 0.2), radius: isHovered ? 12 : 6, y: isHovered ? 6 : 3)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .accessibilityLabel(Text("\(person.name)\(person.role.map { ", \($0)" } ?? "")"))
    }
}

// MARK: - Cast & Crew Section (details page)

/// Horizontal row of cast/crew (guest stars for episodes). Tapping a person
/// calls `onPersonTap`.
struct DetailsCastSection: View {
    @ObservedObject var vm: DetailsViewModel
    var onPersonTap: (CastCrewCard.Person) -> Void

    @Environment(\.flixorTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            HStack(spacing: DS.Space.controlGap) {
                Text(vm.isEpisode && !vm.guestStars.isEmpty ? "Guest Stars" : "Cast & Crew")
                    .font(.flixor(.title1, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Image(systemName: "chevron.right")
                    .font(.flixorIcon(DS.Icon.sm, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: DS.Space.s20) {
                    // Offsets as ids: a person can be both cast and crew.
                    ForEach(Array(people.enumerated()), id: \.offset) { _, person in
                        CastCrewCircleCard(person: person, onTap: { onPersonTap(person) })
                    }
                }
            }
        }
    }

    /// Cast (or guest stars for episodes) followed by key crew.
    private var people: [CastCrewCard.Person] {
        var people: [CastCrewCard.Person] = []
        if vm.isEpisode && !vm.guestStars.isEmpty {
            for g in vm.guestStars.prefix(12) {
                people.append(CastCrewCard.Person(id: g.id, name: g.name, role: g.role, image: g.profile))
            }
        } else {
            for c in vm.cast.prefix(12) {
                people.append(CastCrewCard.Person(id: c.id, name: c.name, role: c.role, image: c.profile))
            }
        }
        for c in vm.crew.prefix(4) {
            people.append(CastCrewCard.Person(id: c.id, name: c.name, role: c.job, image: c.profile))
        }
        return people
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
        .accessibilityLabel(Text("\(person.name)\(person.role.map { ", \($0)" } ?? "")"))
    }

    private func initials(for name: String) -> String {
        let parts = name.components(separatedBy: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}

private struct CastCrewSection: View {
    let cast: [DetailsViewModel.Person]
    let crew: [DetailsViewModel.CrewPerson]
    let layout: DetailsLayoutMetrics
    var onPersonTap: (CastCrewCard.Person) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            DetailsSectionHeader(title: "Cast & Crew")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: layout.castGridMinimum), spacing: 20)], spacing: 24) {
                ForEach(Array(people.prefix(15))) { person in
                    CastCrewCard(person: person, onTap: { onPersonTap(person) })
                }
            }
        }
    }

    private var people: [CastCrewCard.Person] {
        var seen = Set<String>()
        var combined: [CastCrewCard.Person] = []
        for c in cast {
            if seen.insert(c.id).inserted {
                combined.append(CastCrewCard.Person(id: c.id, name: c.name, role: nil, image: c.profile))
            }
        }
        for m in crew {
            if seen.insert(m.id).inserted {
                combined.append(CastCrewCard.Person(id: m.id, name: m.name, role: m.job, image: m.profile))
            }
        }
        return combined
    }
}

private struct TechnicalDetailsSection: View {
    let version: DetailsViewModel.VersionDetail
    let layout: DetailsLayoutMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            DetailsSectionHeader(title: "Technical Details")

            // Main technical specs grid
            LazyVGrid(columns: [GridItem(.adaptive(minimum: layout.technicalGridMinimum), spacing: 16)], spacing: 16) {
                ForEach(technicalPairs(), id: \.0) { pair in
                    TechnicalInfoTile(label: pair.0, value: pair.1)
                }
            }

            // Audio & Subtitle tracks
            if !version.audioTracks.isEmpty || !version.subtitleTracks.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    if !version.audioTracks.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Audio Tracks")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.6))
                                .textCase(.uppercase)
                            FlowChipGroup(texts: version.audioTracks.map { $0.name })
                        }
                    }
                    if !version.subtitleTracks.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Subtitles")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.6))
                                .textCase(.uppercase)
                            FlowChipGroup(texts: version.subtitleTracks.map { $0.name })
                        }
                    }
                }
            }
        }
    }

    private func technicalPairs() -> [(String, String)] {
        var list: [(String, String)] = []
        list.append(("Version", version.label))
        if let reso = version.technical.resolution { list.append(("Resolution", reso)) }
        if let video = version.technical.videoCodec { list.append(("Video", video.uppercased())) }
        if let profile = version.technical.videoProfile, !profile.isEmpty { list.append(("Profile", profile.uppercased())) }
        if let audio = version.technical.audioCodec { list.append(("Audio", audio.uppercased())) }
        if let channels = version.technical.audioChannels { list.append(("Channels", "\(channels)")) }
        if let bitrate = version.technical.bitrate {
            let mbps = Double(bitrate) / 1000.0
            list.append(("Bitrate", String(format: "%.1f Mbps", mbps)))
        }
        if let size = version.technical.fileSizeMB {
            if size >= 1024 {
                list.append(("File Size", String(format: "%.2f GB", size / 1024.0)))
            } else {
                list.append(("File Size", String(format: "%.0f MB", size)))
            }
        }
        if let runtime = version.technical.durationMin {
            list.append(("Runtime", "\(runtime)m"))
        }
        if let subs = version.technical.subtitleCount, subs > 0 {
            list.append(("Subtitles", "\(subs)"))
        }
        return list
    }
}

// MARK: - Production Section
private struct ProductionSection: View {
    let title: String
    let companies: [DetailsViewModel.ProductionCompany]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailsSectionHeader(title: title)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(companies) { company in
                        VStack(spacing: 8) {
                            if let logoURL = company.logoURL {
                                CachedAsyncImage(url: logoURL)
                                    .frame(width: 80, height: 40)
                                    .background(Color.white.opacity(0.9))
                                    .cornerRadius(6)
                            } else {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white.opacity(0.1))
                                    .frame(width: 80, height: 40)
                                    .overlay(
                                        Image(systemName: "building.2")
                                            .foregroundStyle(.white.opacity(0.4))
                                    )
                            }
                            Text(company.name)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(width: 80)
                        }
                    }
                }
            }
        }
    }
}

private struct TechnicalInfoTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.95))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

private struct DetailsSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(.white.opacity(0.95))
    }
}

private struct FlowChipGroup: View {
    let texts: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(texts, id: \.self) { text in
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                            )
                    )
            }
        }
    }
}
