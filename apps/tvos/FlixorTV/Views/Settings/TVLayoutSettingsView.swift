import SwiftUI
import FlixorKit

struct TVLayoutSourceOption: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
}

struct TVLayoutSettingsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case homeLayout
        case homeContent
        case detailPage
        case focusedPoster
        case posterCardStyle

        var id: String { rawValue }

        var title: String {
            switch self {
            case .homeLayout: return "Home Layout"
            case .homeContent: return "Home Content"
            case .detailPage: return "Detail Page"
            case .focusedPoster: return "Focused Poster"
            case .posterCardStyle: return "Poster Card Style"
            }
        }

        var subtitle: String {
            switch self {
            case .homeLayout: return "Choose the overall home browsing style and hero composition."
            case .homeContent: return "Control which content labels and metadata surfaces appear on home."
            case .detailPage: return "Tune metadata emphasis and extra modules on title details."
            case .focusedPoster: return "Mirror Nuvio-style dwell and preview behavior."
            case .posterCardStyle: return "Set poster density and card rounding across rails and grids."
            }
        }
    }

    @EnvironmentObject private var profileSettings: TVProfileSettings
    @Environment(\.tvThemePalette) private var theme
    @State private var expandedSections = Set(Section.allCases)

    let heroSourceOptions: [TVLayoutSourceOption]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Section.allCases) { section in
                TVSettingsDisclosurePanel(
                    title: section.title,
                    subtitle: section.subtitle,
                    isExpanded: binding(for: section)
                ) {
                    sectionContent(section)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionContent(_ section: Section) -> some View {
        switch section {
        case .homeLayout:
            TVSettingsChoiceRow(
                title: "Home Layout",
                subtitle: "Modern hero rails, classic rows, or grid browsing",
                selection: $profileSettings.homeLayoutMode,
                options: TVHomeLayoutMode.allCases.map { TVSettingsChoice(value: $0, label: $0.displayName) }
            )

            TVSettingsChoiceRow(
                title: "Hero Presentation",
                subtitle: "Use the rotating carousel or billboard hero treatment",
                selection: $profileSettings.heroPresentationMode,
                options: TVHeroPresentationMode.allCases.map { TVSettingsChoice(value: $0, label: $0.displayName) }
            )
            .disabled(profileSettings.homeLayoutMode != .modern || !profileSettings.showHeroSection)

            TVSettingsToggleRow(
                title: "Modern Landscape Posters",
                subtitle: "Prefer landscape rows in the modern layout where supported",
                isOn: $profileSettings.modernLandscapePostersEnabled
            )
            .disabled(profileSettings.homeLayoutMode != .modern)

            TVSettingsChoiceRow(
                title: "Continue Watching",
                subtitle: "Choose the primary card shape for resume content",
                selection: $profileSettings.continueWatchingCardShape,
                options: TVRailCardShape.allCases.map { TVSettingsChoice(value: $0, label: $0.displayName) }
            )

            TVSettingsChoiceRow(
                title: "Default Rail Shape",
                subtitle: "Default poster style for home rails",
                selection: $profileSettings.defaultRailCardShape,
                options: TVRailCardShape.allCases.map { TVSettingsChoice(value: $0, label: $0.displayName) }
            )

            TVSettingsPanel(title: "Hero Sources", subtitle: "Zero selected means automatic source selection") {
                if heroSourceOptions.isEmpty {
                    Text("Sources will appear here after Plex libraries load.")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(theme.textTertiary)
                } else {
                    ForEach(heroSourceOptions) { option in
                        TVSettingsToggleRow(
                            title: option.title,
                            subtitle: option.subtitle ?? "Allow this section to drive the hero",
                            isOn: heroSourceBinding(for: option.id)
                        )
                    }
                }
            }
        case .homeContent:
            TVSettingsToggleRow(title: "Show Hero Section", subtitle: "Display the hero at the top of Home", isOn: $profileSettings.showHeroSection)
            TVSettingsToggleRow(title: "Show Search Discover Content", subtitle: "Keep idle discovery content visible in Search", isOn: $profileSettings.showSearchDiscoverContent)
            TVSettingsToggleRow(title: "Show Poster Labels", subtitle: "Reveal titles on focused posters", isOn: $profileSettings.showPosterLabels)
            TVSettingsToggleRow(title: "Show Library Titles", subtitle: "Show titles in library grids and lists", isOn: $profileSettings.showLibraryTitles)
            TVSettingsToggleRow(title: "Show Catalog Provider Name", subtitle: "Show the source/provider label on discovery rails", isOn: $profileSettings.showCatalogAddonName)
            TVSettingsToggleRow(title: "Show Catalog Type Suffix", subtitle: "Append type labels like Movie or Series in discovery contexts", isOn: $profileSettings.showCatalogTypeSuffix)
            TVSettingsToggleRow(title: "Hide Unreleased Content", subtitle: "Suppress titles without a release date yet", isOn: $profileSettings.hideUnreleasedContent)
        case .detailPage:
            TVSettingsToggleRow(title: "Blur Unwatched Episodes", subtitle: "De-emphasize future episodes until they are watched", isOn: $profileSettings.blurUnwatchedEpisodes)
            TVSettingsToggleRow(title: "Show Trailer Button", subtitle: "Expose a trailer CTA in the details hero", isOn: $profileSettings.showTrailerButton)
            TVSettingsToggleRow(title: "Prefer External Metadata", subtitle: "Use TMDB/other enriched metadata ahead of Plex local metadata", isOn: $profileSettings.preferExternalMetadata)
            TVSettingsToggleRow(title: "Show Cast & Crew", subtitle: "Display cast rails and credit blocks", isOn: $profileSettings.showCastCrew)
            TVSettingsToggleRow(title: "Show Related Content", subtitle: "Display more like this and because you watched modules", isOn: $profileSettings.showRelatedContent)
            TVSettingsToggleRow(title: "Show IMDb Rating", subtitle: "Display IMDb badge and score", isOn: $profileSettings.showIMDbRating)
            TVSettingsToggleRow(title: "Show Rotten Tomatoes Critics", subtitle: "Display critic score", isOn: $profileSettings.showRottenTomatoesCritic)
            TVSettingsToggleRow(title: "Show Rotten Tomatoes Audience", subtitle: "Display audience score", isOn: $profileSettings.showRottenTomatoesAudience)
        case .focusedPoster:
            TVSettingsToggleRow(title: "Expand Poster Preview", subtitle: "Turn focused posters into backdrop-style previews", isOn: $profileSettings.focusedPosterExpandEnabled)
            TVSettingsSliderRow(
                title: "Expand Delay",
                subtitle: "Delay before the focused poster expands",
                value: $profileSettings.focusedPosterExpandDelaySeconds,
                range: 0...10,
                step: 1,
                valueText: "\(Int(profileSettings.focusedPosterExpandDelaySeconds))s"
            )
            .disabled(!profileSettings.focusedPosterExpandEnabled)

            TVSettingsToggleRow(title: "Autoplay Trailer on Focus", subtitle: "Attempt trailer preview after focus dwell", isOn: $profileSettings.focusedPosterTrailerEnabled)
            TVSettingsToggleRow(title: "Mute Trailer Preview", subtitle: "Keep focused trailer previews muted", isOn: $profileSettings.focusedPosterTrailerMuted)
                .disabled(!profileSettings.focusedPosterTrailerEnabled)

            TVSettingsChoiceRow(
                title: "Trailer Target",
                subtitle: "Choose where preview media should render",
                selection: $profileSettings.focusedPosterTrailerTarget,
                options: TVFocusedPosterTrailerTarget.allCases.map { TVSettingsChoice(value: $0, label: $0.displayName) }
            )
            .disabled(!profileSettings.focusedPosterTrailerEnabled)
        case .posterCardStyle:
            TVSettingsChoiceRow(
                title: "Width Preset",
                subtitle: "Global poster width and browsing density",
                selection: $profileSettings.posterWidthPreset,
                options: TVPosterWidthPreset.allCases.map { TVSettingsChoice(value: $0, label: $0.displayName) }
            )

            TVSettingsChoiceRow(
                title: "Corner Radius",
                subtitle: "Poster card roundness",
                selection: $profileSettings.posterCornerPreset,
                options: TVPosterCornerPreset.allCases.map { TVSettingsChoice(value: $0, label: $0.displayName) }
            )

            HStack {
                Spacer()
                Button("Reset Poster Style") {
                    profileSettings.posterWidthPreset = .balanced
                    profileSettings.posterCornerPreset = .rounded
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
            }
            .padding(.top, 6)
        }
    }

    private func binding(for section: Section) -> Binding<Bool> {
        Binding(
            get: { expandedSections.contains(section) },
            set: { isExpanded in
                if isExpanded {
                    expandedSections.insert(section)
                } else {
                    expandedSections.remove(section)
                }
            }
        )
    }

    private func heroSourceBinding(for key: String) -> Binding<Bool> {
        Binding(
            get: { profileSettings.heroSourceKeys.contains(key) },
            set: { enabled in
                var keys = Set(profileSettings.heroSourceKeys)
                if enabled {
                    keys.insert(key)
                } else {
                    keys.remove(key)
                }
                profileSettings.heroSourceKeys = Array(keys).sorted()
            }
        )
    }
}

private struct TVSettingsDisclosurePanel<Content: View>: View {
    let title: String
    let subtitle: String?
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    @Environment(\.tvThemePalette) private var theme
    @State private var isFocused = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(theme.textPrimary)
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(theme.textTertiary)
                        }
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(isFocused ? theme.focusRing : theme.textSecondary)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(theme.backgroundCard.opacity(isExpanded ? 0.92 : 0.84))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(isFocused ? theme.strokeFocused : theme.strokeDefault, lineWidth: isFocused ? 2 : 1)
                        )
                )
                .scaleEffect(isFocused ? 1.01 : 1.0)
                .animation(.easeOut(duration: UX.focusDur), value: isFocused)
                .noSystemFocusChrome()
            }
            .buttonStyle(.plain)
            .focusable(true) { isFocused = $0 }

            if isExpanded {
                TVSettingsPanel {
                    content()
                }
                .padding(.leading, 18)
            }
        }
    }
}

private struct TVSettingsSliderRow: View {
    let title: String
    let subtitle: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueText: String

    @Environment(\.tvThemePalette) private var theme
    @Environment(\.tvTypography) private var typography

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(typography.label)
                        .foregroundStyle(theme.textPrimary)
                    Text(subtitle)
                        .font(typography.meta)
                        .foregroundStyle(theme.textTertiary)
                }
                Spacer()
                Text(valueText)
                    .font(typography.label)
                    .foregroundStyle(theme.textSecondary)
            }

            HStack(spacing: 14) {
                TVSettingsIconButton(systemName: "minus") {
                    value = max(range.lowerBound, value - step)
                }
                .disabled(value <= range.lowerBound)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(theme.surfaceGlass)
                        Capsule()
                            .fill(theme.accent)
                            .frame(width: proxy.size.width * progress)
                    }
                }
                .frame(height: 10)

                TVSettingsIconButton(systemName: "plus") {
                    value = min(range.upperBound, value + step)
                }
                .disabled(value >= range.upperBound)
            }
        }
        .padding(.vertical, 4)
    }

    private var progress: CGFloat {
        let span = max(range.upperBound - range.lowerBound, 0.0001)
        return CGFloat((value - range.lowerBound) / span)
    }
}
