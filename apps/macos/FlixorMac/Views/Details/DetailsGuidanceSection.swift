//
//  DetailsGuidanceSection.swift
//  FlixorMac
//
//  Parents Guide on Details, from MyBluray: the age rating and the reason
//  given for it, Common Sense Media's age and scores, and IMDb's parents
//  guide (how strong each category is, the vote split, and what happens,
//  in a bottom panel, with spoilers hidden until clicked). Each part follows its switch in
//  Settings → MyBluray and the section hides itself when nothing is left.
//

import SwiftUI

/// What the section can show for a title, given the settings.
struct DetailsGuidanceContent {
    var certificate: Certificate?
    var commonSense: MBGuidance?
    var imdb: MBParentsGuide?

    struct Certificate {
        let rating: String
        let reason: String?
        let advisories: [String]
    }

    var isEmpty: Bool { certificate == nil && commonSense == nil && imdb == nil }

    @MainActor
    init(title: MBTitle?, guide: MBParentsGuide?, settings: MyBluraySettingsStore) {
        if settings.isOn(.ageRatings) {
            // Apple's certificate carries the reason; IMDb's has one too.
            let certificates = title?.certifications ?? []
            let best = certificates.first(where: { ($0.explanation ?? "").isEmpty == false }) ?? certificates.first
            var candidate: Certificate?
            if let value = best?.value, !value.isEmpty {
                candidate = Certificate(rating: value,
                                        reason: best?.explanation ?? guide?.certification?.reason,
                                        advisories: best?.advisories ?? [])
            } else if let rating = guide?.certification?.rating, !rating.isEmpty, rating.lowercased() != "not rated" {
                candidate = Certificate(rating: rating, reason: guide?.certification?.reason, advisories: [])
            }
            // A bare "PG" repeats the hero's badge; show the card only with a reason or advisories.
            if let candidate, !(candidate.reason ?? "").isEmpty || !candidate.advisories.isEmpty {
                certificate = candidate
            }
        }
        if settings.isOn(.commonSense) {
            commonSense = title?.parentalGuidance.first(where: { $0.recommendedAge != nil || !$0.categories.isEmpty })
        }
        if settings.isOn(.imdbGuide), let guide, !guide.isEmpty {
            imdb = guide
        }
    }
}

struct DetailsGuidanceSection: View {
    let content: DetailsGuidanceContent

    @Environment(\.flixorTheme) private var theme
    @ObservedObject private var settings = MyBluraySettingsStore.shared
    @State private var width: CGFloat = 0

    /// From this width the three cards share one row.
    private static let oneRowWidth: CGFloat = 1240

    var body: some View {
        VStack(alignment: .leading, spacing: DetailsSectionStyle.headingGap) {
            DetailsSectionHeading("Parents Guide")
            if width >= Self.oneRowWidth {
                oneRow
            } else {
                stacked
            }
        }
        .readContentWidth(into: $width)
    }

    /// Wide windows: age rating, Common Sense and the IMDb guide side by side.
    private var oneRow: some View {
        HStack(alignment: .top, spacing: DS.Space.s16) {
            if let certificate = content.certificate {
                certificateCard(certificate).frame(width: 300)
            }
            if let commonSense = content.commonSense {
                commonSenseCard(commonSense).frame(width: 400)
            }
            if let imdb = content.imdb {
                imdbCard(imdb)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func imdbCard(_ guide: MBParentsGuide) -> some View {
        IMDbGuideCard(guide: guide, showsDescriptions: settings.isOn(.guideDescriptions))
    }

    @ViewBuilder private var stacked: some View {
        VStack(alignment: .leading, spacing: DetailsSectionStyle.headingGap) {
            if content.certificate != nil || content.commonSense != nil {
                HStack(alignment: .top, spacing: DS.Space.s16) {
                    if let certificate = content.certificate {
                        certificateCard(certificate)
                            // Short content; next to Common Sense it only needs a third.
                            .frame(maxWidth: content.commonSense == nil ? .infinity : 380)
                    }
                    if let commonSense = content.commonSense {
                        commonSenseCard(commonSense)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            if let imdb = content.imdb {
                imdbCard(imdb)
            }
        }
    }

    // MARK: - Certificate

    private func certificateCard(_ certificate: DetailsGuidanceContent.Certificate) -> some View {
        GuidanceCard(title: "Age Rating") {
            HStack(alignment: .top, spacing: DS.Space.s12) {
                Text(certificate.rating)
                    .font(.flixor(.title3, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, DS.Space.s8)
                    .padding(.vertical, DS.Space.s4)
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.r4).strokeBorder(theme.textSecondary, lineWidth: 1.5))
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    if let reason = certificate.reason, !reason.isEmpty {
                        Text(Self.sentenceCase(reason))
                            .flixorFont(.callout)
                            .foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !certificate.advisories.isEmpty {
                        // Pills keep one line each and wrap onto new rows, left aligned.
                        SearchChipFlowLayout(spacing: DS.Space.s6, lineSpacing: DS.Space.s6) {
                            ForEach(certificate.advisories, id: \.self) { advisory in
                                Text(advisory)
                                    .font(.flixor(.caption, weight: .medium))
                                    .foregroundStyle(theme.textSecondary)
                                    .lineLimit(1)
                                    .fixedSize()
                                    .padding(.horizontal, DS.Space.s10)
                                    .frame(height: 24)
                                    .background(Capsule().fill(theme.hoverFill))
                                    .overlay(Capsule().strokeBorder(theme.separator, lineWidth: DS.Border.thin))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    /// "for intense sequences…" reads as a fragment on its own; start it with a capital.
    private static func sentenceCase(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    // MARK: - Common Sense

    private func commonSenseCard(_ guidance: MBGuidance) -> some View {
        GuidanceCard(title: "Common Sense Media") {
            VStack(alignment: .leading, spacing: DS.Space.s12) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s10) {
                    if let age = guidance.recommendedAge {
                        Text("Age \(age)+")
                            .font(.flixor(.title3, weight: .bold))
                            .foregroundStyle(theme.textPrimary)
                    }
                    if let summary = guidance.summary, !summary.isEmpty {
                        Text(summary)
                            .flixorFont(.callout)
                            .foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !guidance.categories.isEmpty {
                    Grid(alignment: .leading, horizontalSpacing: DS.Space.s16, verticalSpacing: DS.Space.s6) {
                        ForEach(Array(guidance.categories.enumerated()), id: \.offset) { _, category in
                            GridRow {
                                Text(category.name)
                                    .font(.flixor(.caption))
                                    .foregroundStyle(theme.textSecondary)
                                SegmentBar(value: Int((category.value ?? 0).rounded()),
                                           segments: Int(category.scale ?? 5),
                                           color: Self.commonSenseColor(category.name))
                            }
                        }
                    }
                }
            }
        }
    }

    /// Positive categories in green; content concerns in amber.
    private static func commonSenseColor(_ name: String) -> Color {
        name.lowercased().hasPrefix("positive") || name.lowercased().contains("educational")
            ? Color(hex: "34C759") : Color(hex: "FF9F0A")
    }
}

// MARK: - IMDb parents guide

private struct IMDbGuideCard: View {
    let guide: MBParentsGuide
    let showsDescriptions: Bool

    @Environment(\.flixorTheme) private var theme

    var body: some View {
        GuidanceCard(title: "IMDb Parents Guide") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(guide.categories.enumerated()), id: \.element.category) { index, category in
                    if index > 0 {
                        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                    }
                    categoryRow(category, index: index)
                }
                footer
                    .padding(.top, DS.Space.s12)
            }
        }
    }

    /// Opens the category in the bottom panel (like a Trakt comment).
    private func categoryRow(_ category: MBParentsGuide.Category, index: Int) -> some View {
        let canOpen = showsDescriptions && !category.descriptions.isEmpty
        return Button {
            guard canOpen else { return }
            ParentsGuidePopupState.shared.open(guide, at: index)
        } label: {
            HStack(spacing: DS.Space.s12) {
                Text(category.label ?? category.category)
                    .font(.flixor(.callout, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                    .frame(width: 200, alignment: .leading)
                SeverityPill(severity: category.severity, label: category.severityLabel)
                if let agreement = VoteSummary(category).agreement {
                    Text(agreement)
                        .font(.flixor(.caption))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: DS.Space.s8)
                if canOpen {
                    Text("\(category.descriptions.count)")
                        .font(.flixor(.caption, weight: .medium))
                        .foregroundStyle(theme.textTertiary)
                    Image(systemName: "chevron.right")
                        .font(.flixorIcon(DS.Icon.xs, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .padding(.vertical, DS.Space.s10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(canOpen ? "Show what happens" : "")
    }

    private var footer: some View {
        HStack(spacing: DS.Space.s6) {
            Spacer(minLength: DS.Space.s8)
            if let link = guide.websiteUrl.flatMap(URL.init(string:)) {
                Link(destination: link) {
                    Text("View on IMDb ↗")
                        .font(.flixor(.caption, weight: .semibold))
                }
            }
        }
    }
}

// MARK: - Category panel (like a Trakt comment)

@MainActor
final class ParentsGuidePopupState: ObservableObject {
    static let shared = ParentsGuidePopupState()

    @Published private(set) var guide: MBParentsGuide?
    @Published var index: Int?
    /// Spoiler descriptions revealed this time the panel is open.
    @Published var revealed: Set<String> = []

    /// Categories that have something to read.
    var categories: [MBParentsGuide.Category] {
        (guide?.categories ?? []).filter { !$0.descriptions.isEmpty }
    }

    func open(_ guide: MBParentsGuide, at fullIndex: Int) {
        self.guide = guide
        let target = guide.categories[fullIndex].category
        index = categories.firstIndex { $0.category == target } ?? 0
        revealed = []
    }

    func close() { index = nil }

    func step(_ offset: Int) {
        guard let index else { return }
        let next = index + offset
        if categories.indices.contains(next) { self.index = next }
    }
}

struct ParentsGuidePopup: View {
    @ObservedObject private var state = ParentsGuidePopupState.shared
    @ObservedObject private var settings = MyBluraySettingsStore.shared

    @Environment(\.flixorTheme) private var theme
    @Environment(\.windowMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            if let index = state.index, state.categories.indices.contains(index) {
                theme.scrim(DS.Opacity.scrimMedium)
                    .ignoresSafeArea()
                    .onTapGesture { state.close() }
                    .transition(.opacity)
                    .accessibilityHidden(true)

                panel(state.categories[index], index: index)
                    .inPageModal(onDismiss: { state.close() })
                    .background(EscapeKeyButton { state.close() })
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(reduceMotion ? DS.Motion.quick : DS.Motion.standard, value: state.index != nil)
    }

    private func panel(_ category: MBParentsGuide.Category, index: Int) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            Capsule(style: .continuous)
                .fill(theme.separatorStrong)
                .frame(width: 40, height: 4)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            HStack(spacing: DS.Space.s10) {
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    Text(category.label ?? category.category)
                        .flixorFont(.bodyLarge, weight: .semibold)
                        .foregroundStyle(theme.textPrimary)
                    HStack(spacing: DS.Space.s10) {
                        SeverityPill(severity: category.severity, label: category.severityLabel)
                        if let breakdown = VoteSummary(category).breakdown {
                            Text(breakdown)
                                .flixorFont(.caption)
                                .foregroundStyle(theme.textTertiary)
                        }
                    }
                }
                Spacer(minLength: DS.Space.s12)
                pager("chevron.left", label: "Previous category", enabled: index > 0, key: .leftArrow) { state.step(-1) }
                Text(verbatim: "\(index + 1) / \(state.categories.count)")
                    .flixorFont(.footnote, weight: .medium)
                    .foregroundStyle(theme.textSecondary)
                    .monospacedDigit()
                pager("chevron.right", label: "Next category", enabled: index < state.categories.count - 1, key: .rightArrow) { state.step(1) }
            }

            ViewThatFits(in: .vertical) {
                descriptions(category)
                ScrollView { descriptions(category) }
            }
            .id(category.category)
        }
        .padding(.horizontal, DS.Space.s24)
        .padding(.top, DS.Space.s12)
        .padding(.bottom, DS.Space.s24)
        .frame(width: min(760, metrics.width - DS.Space.s40))
        .frame(maxHeight: metrics.height * 0.7)
        .fixedSize(horizontal: false, vertical: true)
        .background(UnevenTopRoundedRectangle(radius: DS.Radius.r24).fill(theme.surfaceElevated))
        .overlay(UnevenTopRoundedRectangle(radius: DS.Radius.r24).stroke(theme.separator, lineWidth: DS.Border.thin))
        .contentShape(Rectangle())
        .onTapGesture {} // A click on the panel must not reach the scrim.
        .accessibilityAddTraits(.isModal)
    }

    private func descriptions(_ category: MBParentsGuide.Category) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s12) {
            ForEach(Array(category.descriptions.enumerated()), id: \.offset) { offset, description in
                let key = description.id ?? "\(category.category)-\(offset)"
                let hidden = description.isSpoiler == true && !settings.isOn(.revealSpoilers) && !state.revealed.contains(key)
                HStack(alignment: .top, spacing: DS.Space.s10) {
                    Circle().fill(theme.textTertiary).frame(width: 5, height: 5).padding(.top, 9)
                    if hidden {
                        Button { state.revealed.insert(key) } label: {
                            Text("Spoiler · click to reveal")
                                .flixorParagraph(.bodyLarge)
                                .foregroundStyle(theme.warning)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Reveal spoiler"))
                    } else {
                        Text(description.text)
                            .flixorParagraph(.bodyLarge)
                            .foregroundStyle(theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func pager(_ icon: String, label: LocalizedStringKey, enabled: Bool, key: KeyEquivalent,
                       action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.flixorIcon(DS.Icon.sm, weight: .semibold))
                .foregroundStyle(enabled ? theme.textPrimary : theme.textTertiary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(theme.hoverFill.opacity(enabled ? 1 : 0.4)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .keyboardShortcut(key, modifiers: [])
        .accessibilityLabel(Text(label))
    }
}

// MARK: - Pieces

private struct GuidanceCard<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: () -> Content

    @Environment(\.flixorTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s10) {
            Text(title)
                .textCase(.uppercase)
                .font(.flixor(.caption, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(theme.textTertiary)
            content()
        }
        .padding(DS.Space.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(theme.surfaceOverlay)
        )
    }
}

/// None / Mild / Moderate / Severe, coloured by strength.
private struct SeverityPill: View {
    let severity: String?
    let label: String?

    var body: some View {
        Text(label ?? (severity ?? "").capitalized)
            .font(.flixor(.caption, weight: .bold))
            .foregroundStyle(color)
            .frame(width: 76)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.16)))
    }

    private var color: Color { Self.color(severity) }

    static func color(_ severity: String?) -> Color {
        switch severity {
        case "severe": return Color(hex: "FF453A")
        case "moderate": return Color(hex: "FF9F0A")
        case "mild": return Color(hex: "FFD60A")
        default: return Color(hex: "8E8E93")
        }
    }
}

/// How IMDb users voted, in words: "60% of 949 voters" for the row, and
/// "None 1% · Mild 12% · Moderate 60% · Severe 27%" in the panel.
private struct VoteSummary {
    let shares: [(label: String, percent: Int, key: String)]
    let total: Int
    let winner: String?

    init(_ category: MBParentsGuide.Category) {
        let votes = category.votes
        let parts: [(String, String, Int)] = [
            ("none", String(localized: "None"), votes?.none ?? 0),
            ("mild", String(localized: "Mild"), votes?.mild ?? 0),
            ("moderate", String(localized: "Moderate"), votes?.moderate ?? 0),
            ("severe", String(localized: "Severe"), votes?.severe ?? 0),
        ]
        let sum = parts.reduce(0) { $0 + $1.2 }
        total = category.totalVotes ?? sum
        shares = sum == 0 ? [] : parts.map { ($0.1, Int((Double($0.2) * 100 / Double(sum)).rounded()), $0.0) }
        winner = category.severity
    }

    /// Share of voters who picked the severity shown.
    var agreement: String? {
        guard total > 0, let share = shares.first(where: { $0.key == winner }) else {
            return total > 0 ? String(localized: "\(total.formatted()) voters") : nil
        }
        return String(localized: "\(share.percent)% of \(total.formatted()) voters")
    }

    var breakdown: String? {
        guard !shares.isEmpty else { return nil }
        return shares.map { "\($0.label) \($0.percent)%" }.joined(separator: " · ")
            + " · " + String(localized: "\(total.formatted()) voters")
    }
}

/// Common Sense's 0–5 scale as segments.
private struct SegmentBar: View {
    let value: Int
    let segments: Int
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(segments, 1), id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(index < value ? color : Color.white.opacity(0.12))
                    .frame(width: 16, height: 5)
            }
        }
        .help("\(value) of \(segments)")
    }
}
