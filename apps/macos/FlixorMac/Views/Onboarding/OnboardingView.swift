//
//  OnboardingView.swift
//  FlixorMac
//
//  Onboarding flow for new users
//

import SwiftUI

struct OnboardingSlide: Identifiable {
    let id: Int
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let description: LocalizedStringKey
    let isConfig: Bool
    let isAddonSetup: Bool

    init(
        id: Int,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        description: LocalizedStringKey,
        isConfig: Bool = false,
        isAddonSetup: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.description = description
        self.isConfig = isConfig
        self.isAddonSetup = isAddonSetup
    }
}

private let plexOnboardingData: [OnboardingSlide] = [
    OnboardingSlide(
        id: 1,
        title: "Welcome to\nFlixor",
        subtitle: "Your Personal Media Hub",
        description: "Stream your entire Plex library with a beautiful, Netflix-inspired experience on any device."
    ),
    OnboardingSlide(
        id: 2,
        title: "Powerful\nIntegrations",
        subtitle: "Connect Your Services",
        description: "Sync with Trakt to track your watch history, get personalized recommendations, and discover new content."
    ),
    OnboardingSlide(
        id: 3,
        title: "Smart\nDiscovery",
        subtitle: "Find What You Love",
        description: "Browse trending content, search across your library and TMDB, and get recommendations tailored to you."
    ),
    OnboardingSlide(
        id: 4,
        title: "Your\nLibrary",
        subtitle: "Beautifully Organized",
        description: "Continue watching across devices, manage your watchlist, and enjoy stunning artwork from TMDB."
    ),
    OnboardingSlide(
        id: 5,
        title: "Customize\nYour Experience",
        subtitle: "Discovery Settings",
        description: "Choose how you want to discover content.",
        isConfig: true
    )
]

private let stremioOnboardingData: [OnboardingSlide] = [
    OnboardingSlide(
        id: 1,
        title: "Welcome to\nFlixor",
        subtitle: "Standalone Stremio Client",
        description: "No Plex account needed. Discovery comes from TMDB and Trakt, and your Stremio addons provide the streams."
    ),
    OnboardingSlide(
        id: 2,
        title: "Add a Stream\nProvider",
        subtitle: "Required",
        description: "Flixor plays direct HTTP streams, so a debrid-backed addon (for example Torrentio configured with Real-Debrid) is what you want. Addons that only return magnet links or torrent info hashes can't be played.",
        isAddonSetup: true
    ),
    OnboardingSlide(
        id: 3,
        title: "Smart\nDiscovery",
        subtitle: "Find What You Love",
        description: "Browse trending and popular titles from TMDB, search everything, and link Trakt for your own history and recommendations."
    ),
    OnboardingSlide(
        id: 4,
        title: "Picks Up Where\nYou Left Off",
        subtitle: "Stored On This Mac",
        description: "Continue watching and My List are kept locally, so they work with no account at all. Link Trakt and they sync too."
    ),
    OnboardingSlide(
        id: 5,
        title: "Customize\nYour Experience",
        subtitle: "Discovery Settings",
        description: "Choose how you want to discover content.",
        isConfig: true
    )
]

struct OnboardingView: View {
    @Environment(\.flixorTheme) private var theme
    let onComplete: () -> Void

    @State private var currentIndex = 0
    @State private var showIndividualSettings = false

    // Profile-scoped discovery settings
    @ObservedObject private var profileSettings = ProfileSettings.shared
    @ObservedObject private var appMode = AppModeStore.shared

    private var onboardingData: [OnboardingSlide] {
        appMode.isStremioOnly ? stremioOnboardingData : plexOnboardingData
    }

    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            // Animated gradient background
            if !theme.pureBlack {
                AnimatedGradientBackground()
            }

            VStack(spacing: 0) {
                // Header with skip and progress
                HStack {
                    Button("Skip") {
                        completeOnboarding()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.white.opacity(0.4))
                    .font(.flixor(.body, weight: .medium))

                    Spacer()

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: DS.Radius.r2)
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 3)

                            RoundedRectangle(cornerRadius: DS.Radius.r2)
                                .fill(Color.white)
                                .frame(width: geo.size.width * progress, height: 3)
                                .animation(DS.Motion.emphasized, value: currentIndex)
                        }
                    }
                    .frame(height: 3)
                    .padding(.leading, DS.Space.s24)
                }
                .padding(.horizontal, DS.Space.s40)
                .padding(.top, 30)
                .padding(.bottom, DS.Space.s20)

                // Content
                TabView(selection: $currentIndex) {
                    ForEach(Array(onboardingData.enumerated()), id: \.element.id) { index, slide in
                        if slide.isConfig {
                            ConfigSlideView(
                                showIndividualSettings: $showIndividualSettings,
                                discoveryDisabled: $profileSettings.discoveryDisabled,
                                showTrendingRows: $profileSettings.showTrendingRows,
                                showTraktRows: $profileSettings.showTraktRows,
                                showPlexPopular: $profileSettings.showPlexPopular,
                                showNewPopularTab: $profileSettings.showNewPopularTab,
                                includeTmdbInSearch: $profileSettings.includeTmdbInSearch,
                                isStremioOnly: appMode.isStremioOnly
                            )
                            .tag(index)
                        } else if slide.isAddonSetup {
                            AddonSetupSlideView(slide: slide)
                                .tag(index)
                        } else {
                            SlideView(slide: slide)
                                .tag(index)
                        }
                    }
                }
                .tabViewStyle(.automatic)

                // Footer with pagination and navigation
                VStack(spacing: DS.Space.s24) {
                    // Pagination dots
                    HStack(spacing: DS.Space.s8) {
                        ForEach(0..<onboardingData.count, id: \.self) { index in
                            RoundedRectangle(cornerRadius: DS.Radius.r4)
                                .fill(Color.white.opacity(index == currentIndex ? 1 : 0.3))
                                .frame(width: index == currentIndex ? 32 : 8, height: 8)
                                .animation(DS.Motion.emphasized, value: currentIndex)
                        }
                    }

                    // Navigation buttons
                    HStack(spacing: DS.Space.s16) {
                        // Previous button
                        Button {
                            withAnimation(DS.Motion.emphasized) {
                                if currentIndex > 0 {
                                    currentIndex -= 1
                                }
                            }
                        } label: {
                            HStack(spacing: DS.Space.s6) {
                                Image(systemName: "chevron.left")
                                    .font(.flixorIcon(DS.Icon.sm, weight: .semibold))
                                Text("Back")
                                    .font(.flixor(.body, weight: .medium))
                            }
                            .foregroundColor(.white.opacity(currentIndex > 0 ? 0.7 : 0.2))
                            .frame(width: 100, height: 50)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(DS.Radius.r10)
                        }
                        .buttonStyle(.plain)
                        .disabled(currentIndex == 0)

                        // Next / Get Started button
                        Button {
                            if currentIndex == onboardingData.count - 1 {
                                completeOnboarding()
                            } else {
                                withAnimation(DS.Motion.emphasized) {
                                    currentIndex += 1
                                }
                            }
                        } label: {
                            HStack(spacing: DS.Space.s6) {
                                Text(currentIndex == onboardingData.count - 1 ? "Get Started" : "Next")
                                    .font(.flixor(.body, weight: .semibold))
                                if currentIndex < onboardingData.count - 1 {
                                    Image(systemName: "chevron.right")
                                        .font(.flixorIcon(DS.Icon.sm, weight: .semibold))
                                }
                            }
                            .foregroundColor(currentIndex == onboardingData.count - 1 ? .black : .white)
                            .frame(width: 140, height: 50)
                            .background(currentIndex == onboardingData.count - 1 ? Color.white : Color.white.opacity(0.15))
                            .cornerRadius(DS.Radius.r10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DS.Space.s40)
                .padding(.bottom, DS.Space.s40)
                .animation(DS.Motion.emphasized, value: currentIndex)
            }
        }
        .onChange(of: profileSettings.discoveryDisabled) { newValue in
            if newValue {
                // When Library Only Mode is enabled, disable all discovery features
                profileSettings.setDiscoveryDisabled(true)
            }
        }
    }

    private var progress: Double {
        Double(currentIndex) / Double(onboardingData.count - 1)
    }

    private func completeOnboarding() {
        profileSettings.hasCompletedOnboarding = true
        onComplete()
    }
}

// MARK: - Slide View

private struct SlideView: View {
    let slide: OnboardingSlide

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            Text(slide.title)
                .font(.system(size: 52, weight: .heavy))
                .foregroundColor(.white)
                .lineSpacing(-8)

            Text(slide.subtitle)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))

            Text(slide.description)
                .font(.flixor(.bodyLarge))
                .foregroundColor(.white.opacity(0.4))
                .lineSpacing(6)
                .frame(maxWidth: 400, alignment: .leading)

            Spacer()
        }
        .padding(.horizontal, DS.Space.s60)
        .padding(.top, DS.Space.s60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Addon Setup Slide View

/// Stremio-only onboarding step. Without a stream-capable addon installed the app
/// has nothing to play, so this is the one setup action that actually matters.
private struct AddonSetupSlideView: View {
    let slide: OnboardingSlide

    @State private var showingAddons = false
    @State private var streamAddonCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            Text(slide.title)
                .font(.system(size: 52, weight: .heavy))
                .foregroundColor(.white)
                .lineSpacing(-8)

            Text(slide.subtitle)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))

            Text(slide.description)
                .font(.flixor(.bodyLarge))
                .foregroundColor(.white.opacity(0.4))
                .lineSpacing(6)
                .frame(maxWidth: 460, alignment: .leading)

            HStack(spacing: DS.Space.s12) {
                Button {
                    showingAddons = true
                } label: {
                    Text(streamAddonCount > 0 ? "Manage Addons" : "Install an Addon")
                        .font(.flixor(.body, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(width: 180, height: 44)
                        .background(Color.white)
                        .cornerRadius(DS.Radius.r10)
                }
                .buttonStyle(.plain)

                HStack(spacing: DS.Space.s6) {
                    Image(systemName: streamAddonCount > 0 ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(streamAddonCount > 0 ? .green : .orange)
                    Text(statusText)
                        .font(.flixor(.callout))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(.top, DS.Space.s8)

            Spacer()
        }
        .padding(.horizontal, DS.Space.s60)
        .padding(.top, DS.Space.s60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showingAddons, onDismiss: { Task { await refreshCount() } }) {
            StremioAddonsView()
        }
        .task { await refreshCount() }
    }

    private var statusText: String {
        switch streamAddonCount {
        case 0: return String(localized: "No stream provider installed yet")
        default: return String(localized: "\(streamAddonCount) stream providers installed")
        }
    }

    private func refreshCount() async {
        await StremioService.shared.ensureInitialized()
        let summaries = await StremioService.shared.getAddonSummary()
        streamAddonCount = summaries.filter { $0.streamCapable }.count
    }
}

// MARK: - Config Slide View

private struct ConfigSlideView: View {
    @Binding var showIndividualSettings: Bool
    @Binding var discoveryDisabled: Bool
    @Binding var showTrendingRows: Bool
    @Binding var showTraktRows: Bool
    @Binding var showPlexPopular: Bool
    @Binding var showNewPopularTab: Bool
    @Binding var includeTmdbInSearch: Bool
    let isStremioOnly: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s20) {
                Text("Customize Your Experience")
                    .font(.flixor(.largeTitle, weight: .heavy))
                    .foregroundColor(.white)

                Text("Choose how you want to discover content")
                    .font(.flixor(.bodyLarge))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.bottom, DS.Space.s8)

                // Library Only Mode Card - Plex-library-only makes no sense without Plex
                if !isStremioOnly {
                libraryOnlyModeCard
                }

                // Expand Individual Settings - always expanded in Stremio-only mode,
                // since Library Only Mode is the only thing it's an alternative to.
                if !isStremioOnly {
                    expandToggle
                }

                if isStremioOnly || (showIndividualSettings && !discoveryDisabled) {
                    individualSettings
                }

                infoText

                Spacer(minLength: 80)
            }
            .padding(.horizontal, DS.Space.s60)
            .padding(.top, DS.Space.s40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var libraryOnlyModeCard: some View {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: DS.Space.s16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: DS.Radius.r12)
                                .fill(Color.red.opacity(0.15))
                                .frame(width: 48, height: 48)
                            Image(systemName: "eye.slash.fill")
                                .font(.flixorIcon(DS.Icon.lg))
                                .foregroundColor(.red)
                        }

                        VStack(alignment: .leading, spacing: DS.Space.s4) {
                            Text("Library Only Mode")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                            Text("Turn off all discovery features. Only show content from your Plex library.")
                                .font(.flixor(.callout))
                                .foregroundColor(.white.opacity(0.5))
                                .lineLimit(2)
                        }

                        Spacer()

                        Toggle("", isOn: $discoveryDisabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    .padding(DS.Space.s20)
                }
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.r16)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.r16)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
    }

    private var expandToggle: some View {
                Button {
                    withAnimation(DS.Motion.standard) {
                        showIndividualSettings.toggle()
                    }
                } label: {
                    HStack {
                        Text("Or customize individual settings")
                            .font(.flixor(.body, weight: .medium))
                            .foregroundColor(discoveryDisabled ? .white.opacity(0.2) : .white.opacity(0.5))
                        Image(systemName: showIndividualSettings ? "chevron.up" : "chevron.down")
                            .font(.flixorIcon(DS.Icon.xs))
                            .foregroundColor(discoveryDisabled ? .white.opacity(0.2) : .white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Space.s16)
                }
                .buttonStyle(.plain)
                .disabled(discoveryDisabled)
    }

    private var individualSettings: some View {
                    VStack(spacing: 0) {
                        SettingRowView(
                            icon: "flame.fill",
                            iconColor: .orange,
                            title: "Trending Rows",
                            subtitle: "Show trending content from TMDB",
                            isOn: $showTrendingRows,
                            showDivider: true
                        )

                        SettingRowView(
                            icon: "chart.bar.fill",
                            iconColor: Color(hex: "#ED1C24"),
                            title: "Trakt Rows",
                            subtitle: "Show recommendations from Trakt",
                            isOn: $showTraktRows,
                            showDivider: true
                        )

                        SettingRowView(
                            icon: "play.square.stack.fill",
                            iconColor: Color(hex: "#E5A00D"),
                            title: isStremioOnly ? "Popular Row" : "Popular on Plex",
                            subtitle: isStremioOnly ? "Show a popular titles row" : "Show popular content on Plex",
                            isOn: $showPlexPopular,
                            showDivider: true
                        )

                        SettingRowView(
                            icon: "sparkles",
                            iconColor: .purple,
                            title: "New & Hot Tab",
                            subtitle: "Show New & Hot tab in navigation",
                            isOn: $showNewPopularTab,
                            showDivider: true
                        )

                        SettingRowView(
                            icon: "magnifyingglass",
                            iconColor: .blue,
                            title: "TMDB in Search",
                            subtitle: "Include TMDB results when searching",
                            isOn: $includeTmdbInSearch,
                            showDivider: false
                        )
                    }
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.r16)
                            .fill(Color.white.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.r16)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var infoText: some View {
                HStack(spacing: DS.Space.s8) {
                    Image(systemName: "info.circle")
                        .font(.flixorIcon(DS.Icon.sm))
                        .foregroundColor(.white.opacity(0.4))
                    Text("You can change these settings anytime in Settings → Discovery Mode")
                        .font(.flixor(.callout))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.top, DS.Space.s16)
    }
}

// MARK: - Setting Row View

private struct SettingRowView: View {
    let icon: String
    let iconColor: Color
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    @Binding var isOn: Bool
    let showDivider: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.s12) {
                ZStack {
                    RoundedRectangle(cornerRadius: DS.Radius.r8)
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.flixorIcon(DS.Icon.md))
                        .foregroundColor(iconColor)
                }

                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    Text(title)
                        .font(.flixor(.body, weight: .semibold))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.flixor(.footnote))
                        .foregroundColor(.white.opacity(0.4))
                }

                Spacer()

                Toggle("", isOn: $isOn)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .scaleEffect(0.8)
            }
            .padding(.horizontal, DS.Space.s16)
            .padding(.vertical, DS.Space.s14)

            if showDivider {
                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.leading, DS.Space.s64)
            }
        }
    }
}

// MARK: - Animated Gradient Background

private struct AnimatedGradientBackground: View {
    @State private var animateGradient = false

    var body: some View {
        ZStack {
            // Base gradient
            LinearGradient(
                colors: [
                    Color(hex: "#1a1a2e"),
                    Color(hex: "#16213e"),
                    Color(hex: "#0f0f23")
                ],
                startPoint: animateGradient ? .topLeading : .bottomTrailing,
                endPoint: animateGradient ? .bottomTrailing : .topLeading
            )

            // Floating orbs
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.purple.opacity(0.3), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 400)
                .offset(x: animateGradient ? 150 : -150, y: animateGradient ? -100 : 100)
                .blur(radius: 60)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.blue.opacity(0.2), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 150
                    )
                )
                .frame(width: 300, height: 300)
                .offset(x: animateGradient ? -100 : 100, y: animateGradient ? 150 : -150)
                .blur(radius: 50)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                animateGradient.toggle()
            }
        }
    }
}

#if DEBUG
#Preview {
    OnboardingView(onComplete: {})
        .frame(width: 900, height: 700)
}
#endif
