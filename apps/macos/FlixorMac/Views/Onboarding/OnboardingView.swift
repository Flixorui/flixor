//
//  OnboardingView.swift
//  FlixorMac
//
//  Onboarding flow for new users
//

import SwiftUI

struct OnboardingSlide: Identifiable {
    let id: Int
    let title: String
    let subtitle: String
    let description: String
    let isConfig: Bool

    init(id: Int, title: String, subtitle: String, description: String, isConfig: Bool = false) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.description = description
        self.isConfig = isConfig
    }
}

private let onboardingData: [OnboardingSlide] = [
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

struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var currentIndex = 0
    @State private var showIndividualSettings = false

    // Profile-scoped discovery settings
    @ObservedObject private var profileSettings = ProfileSettings.shared

    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            // Animated gradient background
            AnimatedGradientBackground()

            VStack(spacing: 0) {
                // Header with skip and progress
                HStack {
                    Button("Skip") {
                        completeOnboarding()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.white.opacity(0.4))
                    .font(.system(size: 14, weight: .medium))

                    Spacer()

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 3)

                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white)
                                .frame(width: geo.size.width * progress, height: 3)
                                .animation(.easeInOut(duration: 0.3), value: currentIndex)
                        }
                    }
                    .frame(height: 3)
                    .padding(.leading, 24)
                }
                .padding(.horizontal, 40)
                .padding(.top, 30)
                .padding(.bottom, 20)

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
                                includeTmdbInSearch: $profileSettings.includeTmdbInSearch
                            )
                            .tag(index)
                        } else {
                            SlideView(slide: slide)
                                .tag(index)
                        }
                    }
                }
                .tabViewStyle(.automatic)

                // Footer with pagination and navigation
                VStack(spacing: 24) {
                    // Pagination dots
                    HStack(spacing: 8) {
                        ForEach(0..<onboardingData.count, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(index == currentIndex ? 1 : 0.3))
                                .frame(width: index == currentIndex ? 32 : 8, height: 8)
                                .animation(.easeInOut(duration: 0.3), value: currentIndex)
                        }
                    }

                    // Navigation buttons
                    HStack(spacing: 16) {
                        // Previous button
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                if currentIndex > 0 {
                                    currentIndex -= 1
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Back")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundColor(.white.opacity(currentIndex > 0 ? 0.7 : 0.2))
                            .frame(width: 100, height: 50)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        .disabled(currentIndex == 0)

                        // Next / Get Started button
                        Button {
                            if currentIndex == onboardingData.count - 1 {
                                completeOnboarding()
                            } else {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    currentIndex += 1
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(currentIndex == onboardingData.count - 1 ? "Get Started" : "Next")
                                    .font(.system(size: 14, weight: .semibold))
                                if currentIndex < onboardingData.count - 1 {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                            }
                            .foregroundColor(currentIndex == onboardingData.count - 1 ? .black : .white)
                            .frame(width: 140, height: 50)
                            .background(currentIndex == onboardingData.count - 1 ? Color.white : Color.white.opacity(0.15))
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
                .animation(.easeInOut(duration: 0.3), value: currentIndex)
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
        VStack(alignment: .leading, spacing: 16) {
            Text(slide.title)
                .font(.system(size: 52, weight: .heavy))
                .foregroundColor(.white)
                .lineSpacing(-8)

            Text(slide.subtitle)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))

            Text(slide.description)
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.4))
                .lineSpacing(6)
                .frame(maxWidth: 400, alignment: .leading)

            Spacer()
        }
        .padding(.horizontal, 60)
        .padding(.top, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Customize Your Experience")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundColor(.white)

                Text("Choose how you want to discover content")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.bottom, 8)

                // Library Only Mode Card
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.red.opacity(0.15))
                                .frame(width: 48, height: 48)
                            Image(systemName: "eye.slash.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.red)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Library Only Mode")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                            Text("Turn off all discovery features. Only show content from your Plex library.")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.5))
                                .lineLimit(2)
                        }

                        Spacer()

                        Toggle("", isOn: $discoveryDisabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    .padding(20)
                }
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )

                // Expand Individual Settings
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showIndividualSettings.toggle()
                    }
                } label: {
                    HStack {
                        Text("Or customize individual settings")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(discoveryDisabled ? .white.opacity(0.2) : .white.opacity(0.5))
                        Image(systemName: showIndividualSettings ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12))
                            .foregroundColor(discoveryDisabled ? .white.opacity(0.2) : .white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.plain)
                .disabled(discoveryDisabled)

                // Individual Settings
                if showIndividualSettings && !discoveryDisabled {
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
                            title: "Popular on Plex",
                            subtitle: "Show popular content on Plex",
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
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Info text
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.4))
                    Text("You can change these settings anytime in Settings → Discovery Mode")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.top, 16)

                Spacer(minLength: 80)
            }
            .padding(.horizontal, 60)
            .padding(.top, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Setting Row View

private struct SettingRowView: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let showDivider: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundColor(iconColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                }

                Spacer()

                Toggle("", isOn: $isOn)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .scaleEffect(0.8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if showDivider {
                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.leading, 64)
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
