//
//  PersonIdentityViews.swift
//  FlixorMac
//
//  Identity block of the person page: photo, name, facts (born / died /
//  place of birth / credits), external links and the expandable biography.
//  Laid out as a sidebar on wide windows and as a header on narrow ones.
//

import SwiftUI
import FlixorKit

// MARK: - Dates

enum PersonDates {
    private static let parser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let display: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    static func date(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return parser.date(from: value)
    }

    static func format(_ date: Date) -> String {
        display.string(from: date)
    }

    static func years(from start: Date, to end: Date) -> Int? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar.dateComponents([.year], from: start, to: end).year
    }

    /// "March 3, 1964 (age 60)", or without the age once the person has died.
    static func bornLine(birthday: String?, deathday: String?) -> String? {
        guard let born = date(birthday) else { return nil }
        if date(deathday) != nil { return format(born) }
        if let age = years(from: born, to: Date()), age >= 0 {
            return "\(format(born)) (age \(age))"
        }
        return format(born)
    }

    /// "June 1, 2020 (aged 58)".
    static func diedLine(birthday: String?, deathday: String?) -> String? {
        guard let died = date(deathday) else { return nil }
        if let born = date(birthday), let age = years(from: born, to: died), age >= 0 {
            return "\(format(died)) (aged \(age))"
        }
        return format(died)
    }
}

// MARK: - Avatar

struct PersonAvatar: View {
    let url: URL?
    let name: String
    let size: CGFloat

    @Environment(\.flixorTheme) private var theme

    var body: some View {
        ZStack {
            Circle()
                .fill(theme.accentSoft)
                .frame(width: size, height: size)
            ZStack {
                Circle().fill(theme.surfaceElevated)
                if let url {
                    CachedAsyncImage(url: url, contentMode: .fill) { initialsView }
                } else {
                    initialsView
                }
            }
            .frame(width: size - DS.Space.s14, height: size - DS.Space.s14)
            .clipShape(Circle())
            .overlay(Circle().stroke(theme.separatorStrong, lineWidth: DS.Border.thin))
        }
        .flixorShadow(.card)
        .accessibilityLabel("Photo of \(name)")
    }

    private var initialsView: some View {
        Text(initials)
            .font(.flixor(size > 120 ? .displayLarge : .title1, weight: .bold))
            .foregroundStyle(theme.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var initials: String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}

// MARK: - Facts

struct PersonFact: Identifiable {
    let label: String
    let value: String
    var id: String { label }
}

extension PersonDetailViewModel {
    var facts: [PersonFact] {
        guard let profile else { return [] }
        var facts: [PersonFact] = []
        if let department = knownForDepartment {
            facts.append(PersonFact(label: "Known for", value: department))
        }
        if let born = PersonDates.bornLine(birthday: profile.birthday, deathday: profile.deathday) {
            facts.append(PersonFact(label: "Born", value: born))
        }
        if let died = PersonDates.diedLine(birthday: profile.birthday, deathday: profile.deathday) {
            facts.append(PersonFact(label: "Died", value: died))
        }
        if let place = profile.placeOfBirth?.trimmingCharacters(in: .whitespaces), !place.isEmpty {
            facts.append(PersonFact(label: "Place of birth", value: place))
        }
        if let summary = creditSummary {
            facts.append(PersonFact(label: "Credits", value: summary))
        }
        return facts
    }
}

struct PersonFactsList: View {
    let facts: [PersonFact]
    /// Two columns in the narrow header, one in the sidebar.
    var columns: Int = 1

    @Environment(\.flixorTheme) private var theme

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s24, alignment: .topLeading), count: max(1, columns)),
            alignment: .leading,
            spacing: DS.Space.s14
        ) {
            ForEach(facts) { fact in
                VStack(alignment: .leading, spacing: DS.Space.s4) {
                    PersonSectionLabel(text: fact.label)
                    Text(fact.value)
                        .flixorFont(.body)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

struct PersonSectionLabel: View {
    let text: String
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        Text(text.uppercased())
            .flixorFont(.micro)
            .foregroundStyle(theme.textTertiary)
    }
}

// MARK: - Links

struct PersonLinksRow: View {
    @ObservedObject var viewModel: PersonDetailViewModel
    @Environment(\.flixorTheme) private var theme
    @Environment(\.openURL) private var openURL

    private struct PersonLink: Identifiable {
        let title: String
        let icon: String
        let url: URL
        var id: String { title }
    }

    private var links: [PersonLink] {
        var links: [PersonLink] = []
        if let url = viewModel.imdbURL { links.append(PersonLink(title: "IMDb", icon: "film", url: url)) }
        if let url = viewModel.instagramURL { links.append(PersonLink(title: "Instagram", icon: "camera", url: url)) }
        if let url = viewModel.homepageURL { links.append(PersonLink(title: "Website", icon: "globe", url: url)) }
        return links
    }

    var body: some View {
        let links = self.links
        if !links.isEmpty {
            HStack(spacing: DS.Space.controlGap) {
                ForEach(links) { link in
                    Button {
                        openURL(link.url)
                    } label: {
                        Label(link.title, systemImage: link.icon)
                            .flixorFont(.footnote, weight: .semibold)
                            .foregroundStyle(theme.textSecondary)
                            .padding(.horizontal, DS.Space.s10)
                            .padding(.vertical, DS.Space.s6)
                            .background(Capsule().fill(theme.hoverFill))
                            .overlay(Capsule().stroke(theme.separator, lineWidth: DS.Border.thin))
                    }
                    .buttonStyle(.plain)
                    .help(link.url.absoluteString)
                    .accessibilityLabel("Open \(link.title)")
                }
            }
        }
    }
}

// MARK: - Expandable biography

struct ExpandableText: View {
    let text: String
    var collapsedLineLimit: Int = 8

    @Environment(\.flixorTheme) private var theme
    @State private var isExpanded = false
    @State private var fullHeight: CGFloat = 0
    @State private var collapsedHeight: CGFloat = 0

    private var isTruncated: Bool { fullHeight > collapsedHeight + 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s8) {
            styledText
                .lineLimit(isExpanded ? nil : collapsedLineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: CollapsedHeightKey.self, value: isExpanded ? 0 : proxy.size.height)
                    }
                )
                .background(
                    // Unlimited copy, measured to know whether the text is cut off.
                    styledText
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(key: FullHeightKey.self, value: proxy.size.height)
                            }
                        ),
                    alignment: .topLeading
                )
                .onPreferenceChange(FullHeightKey.self) { fullHeight = $0 }
                .onPreferenceChange(CollapsedHeightKey.self) { value in
                    if value > 0 { collapsedHeight = value }
                }

            if isExpanded || isTruncated {
                Button {
                    withAnimation(DS.Motion.standard) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: DS.Space.s4) {
                        Text(isExpanded ? "Show less" : "Read more")
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.flixorIcon(DS.Icon.xs, weight: .semibold))
                    }
                    .flixorFont(.callout, weight: .semibold)
                    .foregroundStyle(theme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Show less biography" : "Read full biography")
            }
        }
    }

    private var styledText: some View {
        Text(text)
            .flixorParagraph(.body)
            .foregroundStyle(theme.textSecondary)
    }

    private struct FullHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
    }

    private struct CollapsedHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
    }
}

// MARK: - Sidebar (wide windows)

struct PersonIdentitySidebar: View {
    @ObservedObject var viewModel: PersonDetailViewModel
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s24) {
            PersonAvatar(url: viewModel.profileImageURL, name: viewModel.displayName, size: 168)

            Text(viewModel.displayName)
                .flixorFont(.largeTitle)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(3)
                .textSelection(.enabled)
                .accessibilityAddTraits(.isHeader)

            PersonFactsList(facts: viewModel.facts)

            PersonLinksRow(viewModel: viewModel)

            if let biography = viewModel.biography {
                Rectangle()
                    .fill(theme.separator)
                    .frame(height: DS.Border.thin)
                VStack(alignment: .leading, spacing: DS.Space.s10) {
                    PersonSectionLabel(text: "Biography")
                    ExpandableText(text: biography, collapsedLineLimit: 12)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Header (narrow windows)

struct PersonIdentityHeader: View {
    @ObservedObject var viewModel: PersonDetailViewModel
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s24) {
            HStack(alignment: .top, spacing: DS.Space.s28) {
                PersonAvatar(url: viewModel.profileImageURL, name: viewModel.displayName, size: 148)

                VStack(alignment: .leading, spacing: DS.Space.s16) {
                    Text(viewModel.displayName)
                        .flixorFont(.display)
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                        .accessibilityAddTraits(.isHeader)
                    PersonFactsList(facts: viewModel.facts, columns: 2)
                    PersonLinksRow(viewModel: viewModel)
                }
                .padding(.top, DS.Space.s8)
            }

            if let biography = viewModel.biography {
                VStack(alignment: .leading, spacing: DS.Space.s10) {
                    PersonSectionLabel(text: "Biography")
                    ExpandableText(text: biography, collapsedLineLimit: 5)
                        .frame(maxWidth: 900, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
