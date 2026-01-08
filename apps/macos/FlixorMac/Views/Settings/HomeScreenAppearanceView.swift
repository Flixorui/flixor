//
//  HomeScreenAppearanceView.swift
//  FlixorMac
//
//  Visual appearance settings for the home screen
//

import SwiftUI

struct HomeScreenAppearanceView: View {
    @AppStorage("heroLayout") private var heroLayout: String = "billboard"
    @AppStorage("showHeroSection") private var showHeroSection: Bool = true
    @AppStorage("continueWatchingLayout") private var continueWatchingLayout: String = "landscape"
    @AppStorage("rowLayout") private var rowLayout: String = "poster"
    @AppStorage("posterSize") private var posterSize: String = "medium"
    @AppStorage("showPosterTitles") private var showPosterTitles: Bool = true
    @AppStorage("showLibraryTitles") private var showLibraryTitles: Bool = true
    @AppStorage("posterCornerRadius") private var posterCornerRadius: String = "medium"

    @State private var showHeroPreview: Bool = false
    @State private var showContinueWatchingPreview: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Hero Section
            SettingsSectionHeader(title: "Hero Section")
            SettingsGroupCard {
                SettingsRow(icon: "rectangle.inset.filled", iconColor: .blue, title: "Show Hero Section", showDivider: false) {
                    Toggle("", isOn: $showHeroSection).labelsHidden()
                }
            }

            if showHeroSection {
                SettingsGroupCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Hero Layout")
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.top, 12)

                        HStack(spacing: 12) {
                            LayoutOptionButton(
                                title: "Billboard",
                                icon: "rectangle.fill",
                                isSelected: heroLayout == "billboard"
                            ) {
                                heroLayout = "billboard"
                            }

                            LayoutOptionButton(
                                title: "Carousel",
                                icon: "rectangle.stack.fill",
                                isSelected: heroLayout == "carousel"
                            ) {
                                heroLayout = "carousel"
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                    }
                }

                // Hero Layout Preview
                CollapsiblePreviewSection(title: "Hero Preview", isExpanded: $showHeroPreview) {
                    if heroLayout == "billboard" {
                        billboardPreview
                    } else {
                        carouselPreview
                    }
                }
            }

            // Continue Watching Layout
            SettingsSectionHeader(title: "Continue Watching")
            SettingsGroupCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Display Style")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.top, 12)

                    HStack(spacing: 12) {
                        LayoutOptionButton(
                            title: "Landscape",
                            icon: "rectangle.fill",
                            isSelected: continueWatchingLayout == "landscape"
                        ) {
                            continueWatchingLayout = "landscape"
                        }

                        LayoutOptionButton(
                            title: "Poster",
                            icon: "rectangle.portrait.fill",
                            isSelected: continueWatchingLayout == "poster"
                        ) {
                            continueWatchingLayout = "poster"
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }

            // Continue Watching Preview
            CollapsiblePreviewSection(title: "Continue Watching Preview", isExpanded: $showContinueWatchingPreview) {
                if continueWatchingLayout == "landscape" {
                    continueWatchingLandscapePreview
                } else {
                    continueWatchingPosterPreview
                }
            }

            // Poster Display
            SettingsSectionHeader(title: "Poster Display")
            SettingsGroupCard {
                SettingsRow(icon: "textformat", iconColor: .purple, title: "Show Titles") {
                    Toggle("", isOn: $showPosterTitles).labelsHidden()
                }
                SettingsRow(icon: "folder", iconColor: .blue, title: "Show Library Titles") {
                    Toggle("", isOn: $showLibraryTitles).labelsHidden()
                }
                SettingsRow(icon: "arrow.up.left.and.arrow.down.right", iconColor: .green, title: "Poster Size") {
                    Picker("", selection: $posterSize) {
                        Text("Small").tag("small")
                        Text("Medium").tag("medium")
                        Text("Large").tag("large")
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
                SettingsRow(icon: "square.on.square", iconColor: .orange, title: "Corner Radius", showDivider: false) {
                    Picker("", selection: $posterCornerRadius) {
                        Text("None").tag("none")
                        Text("Small").tag("small")
                        Text("Medium").tag("medium")
                        Text("Large").tag("large")
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
            }
        }
    }

    // MARK: - Hero Previews

    private var billboardPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Single large billboard card
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .aspectRatio(21/9, contentMode: .fit)

                // Gradient overlay
                LinearGradient(
                    colors: [.clear, .black.opacity(0.7)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Content
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 120, height: 30)

                    HStack(spacing: 6) {
                        ForEach(["2024", "2h 15m", "PG-13"], id: \.self) { text in
                            Text(text)
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 200, height: 8)

                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white)
                            .frame(width: 60, height: 28)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 60, height: 28)
                    }
                }
                .padding(16)
            }

            Text("Billboard: Single featured item with full-width display")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var carouselPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Multiple carousel cards
            HStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { index in
                    ZStack(alignment: .bottomLeading) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        [Color.blue, Color.indigo],
                                        [Color.purple, Color.pink],
                                        [Color.orange, Color.red]
                                    ][index].map { $0.opacity(0.4) },
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .aspectRatio(16/9, contentMode: .fit)

                        // Gradient
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.6)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        // Content
                        VStack(alignment: .leading, spacing: 4) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.9))
                                .frame(width: 60, height: 16)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.5))
                                .frame(width: 80, height: 6)
                        }
                        .padding(10)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(index == 0 ? Color.white.opacity(0.5) : Color.clear, lineWidth: 2)
                    )
                }
            }

            // Page indicators
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(index == 0 ? Color.white : Color.white.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            .frame(maxWidth: .infinity)

            Text("Carousel: Multiple items with swipe navigation")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Continue Watching Previews

    private var continueWatchingLandscapePreview: some View {
        HStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { index in
                VStack(alignment: .leading, spacing: 6) {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.1))
                            .aspectRatio(16/9, contentMode: .fit)

                        // Progress bar
                        GeometryReader { geo in
                            VStack {
                                Spacer()
                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.3))
                                        .frame(height: 3)

                                    Rectangle()
                                        .fill(Color.blue)
                                        .frame(width: geo.size.width * CGFloat([0.3, 0.65, 0.45][index]), height: 3)
                                }
                            }
                        }

                        // Play icon
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.9))
                    }

                    Text(["Breaking Bad", "The Office", "Stranger Things"][index])
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Text(["S5 E14", "S3 E7", "S4 E2"][index])
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 120)
            }
        }
    }

    private var continueWatchingPosterPreview: some View {
        HStack(spacing: 12) {
            ForEach(0..<4, id: \.self) { index in
                VStack(alignment: .center, spacing: 6) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.1))
                            .aspectRatio(2/3, contentMode: .fit)

                        // Progress ring
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 3)
                            .frame(width: 32, height: 32)

                        Circle()
                            .trim(from: 0, to: CGFloat([0.3, 0.65, 0.45, 0.8][index]))
                            .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .frame(width: 32, height: 32)
                            .rotationEffect(.degrees(-90))

                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white)
                    }

                    Text(["Breaking Bad", "The Office", "Stranger", "Dark"][index])
                        .font(.caption2)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
                .frame(width: 70)
            }
        }
    }
}

// MARK: - Layout Option Button

struct LayoutOptionButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                isSelected
                    ? Color.accentColor
                    : Color(NSColor.controlBackgroundColor)
            )
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.clear : Color(NSColor.separatorColor),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Collapsible Preview Section

struct CollapsiblePreviewSection<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with toggle button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Text(title.uppercased())
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)

                    Spacer()

                    HStack(spacing: 4) {
                        Text(isExpanded ? "Hide" : "Show")
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .buttonStyle(.plain)

            // Collapsible content
            if isExpanded {
                SettingsGroupCard {
                    content()
                        .padding(16)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
