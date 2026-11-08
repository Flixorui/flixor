//
//  ContinueWatchingSettingsView.swift
//  FlixorMac
//
//  Continue Watching display and caching settings
//

import SwiftUI

struct ContinueWatchingSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var profileSettings = ProfileSettings.shared
    @ObservedObject private var rowsStore = HomeRowsStore.shared
    @State private var showPreview: Bool = false

    private var cardStyle: ContinueWatchingCardStyle {
        ContinueWatchingCardStyle(storageValue: profileSettings.continueWatchingLayout)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with close button
            HStack {
                Text("Continue Watching")
                    .font(.flixor(.headline, weight: .semibold))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.flixorIcon(DS.Icon.lg))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, DS.Space.s24)
            .padding(.top, DS.Space.s20)
            .padding(.bottom, DS.Space.s16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s24) {
                    // Layout Section
                    SettingsSectionHeader(title: "Display Layout")
                    SettingsGroupCard {
                        VStack(alignment: .leading, spacing: DS.Space.s12) {
                            Text("Choose how continue watching items appear")
                                .font(.flixor(.footnote))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, DS.Space.s12)
                                .padding(.top, DS.Space.s12)

                            ContinueWatchingStylePicker()
                                .padding(.horizontal, DS.Space.s12)
                                .padding(.bottom, DS.Space.s12)
                        }
                    }

                    // Collapsible Preview Section
                    CollapsiblePreviewSection(title: "Preview", isExpanded: $showPreview) {
                        switch cardStyle {
                        case .landscape: landscapePreview
                        case .poster: posterPreview
                        case .wide: ContinueWatchingWidePreview(blurUpNext: rowsStore.continueWatchingBlurNextUp)
                        }
                    }

                    // Order and spoilers
                    SettingsSectionHeader(title: "Order & Spoilers")
                    SettingsGroupCard {
                        SettingsRow(
                            icon: "arrow.up.arrow.down",
                            iconColor: .indigo,
                            title: "Sort Order",
                            subtitle: "Order of items in the row"
                        ) {
                            Picker("", selection: $rowsStore.continueWatchingSort) {
                                ForEach(ContinueWatchingSort.allCases) { sort in
                                    Text(sort.title).tag(sort)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 170)
                            .accessibilityLabel(Text("Continue Watching sort order"))
                        }
                        SettingsRow(
                            icon: "eye.slash.fill",
                            iconColor: .pink,
                            title: "Blur Next-Up Thumbnails",
                            subtitle: "Hide stills of episodes you haven't started (Wide cards)",
                            showDivider: false
                        ) {
                            Toggle("", isOn: $rowsStore.continueWatchingBlurNextUp)
                                .labelsHidden()
                                .accessibilityLabel(Text("Blur thumbnails of next-up episodes"))
                        }
                    }

                    // Cache Section
                    SettingsSectionHeader(title: "Playback Source Cache")
                    SettingsGroupCard {
                        SettingsRow(icon: "arrow.triangle.2.circlepath.circle.fill", iconColor: .blue, title: "Cache Playback Sources", subtitle: "Reuse recent provider URLs for faster resume", showDivider: !profileSettings.useCachedStreams) {
                            Toggle("", isOn: $profileSettings.useCachedStreams).labelsHidden()
                        }

                        if profileSettings.useCachedStreams {
                            VStack(alignment: .leading, spacing: DS.Space.s8) {
                                Text("Cache Duration")
                                    .font(.flixor(.footnote, weight: .medium))
                                    .padding(.horizontal, DS.Space.s12)

                                Picker("", selection: $profileSettings.streamCacheTTL) {
                                    Text("15 min").tag(900)
                                    Text("30 min").tag(1800)
                                    Text("1 hour").tag(3600)
                                    Text("6 hours").tag(21600)
                                    Text("12 hours").tag(43200)
                                    Text("24 hours").tag(86400)
                                }
                                .pickerStyle(.segmented)
                                .padding(.horizontal, DS.Space.s12)
                                .padding(.bottom, DS.Space.s12)
                            }
                        }
                    }

                    Text("Playback source caching stores recent URLs and provider metadata locally for faster resume across Plex and alternate providers such as Stremio. Disable it if you experience expired or unstable links.")
                        .font(.flixor(.caption))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, DS.Space.s4)
                }
                .padding(DS.Space.s24)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Previews
    // Landscape / poster previews below; the Wide preview is ContinueWatchingWidePreview.

    private var landscapePreview: some View {
        HStack(spacing: DS.Space.s12) {
            ForEach(0..<3, id: \.self) { index in
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: DS.Radius.r8)
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
                            .font(.flixorIcon(DS.Icon.xl))
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

    private var posterPreview: some View {
        HStack(spacing: DS.Space.s12) {
            ForEach(0..<4, id: \.self) { index in
                VStack(alignment: .center, spacing: DS.Space.s6) {
                    ZStack {
                        RoundedRectangle(cornerRadius: DS.Radius.r8)
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
                            .font(.flixor(.micro))
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
