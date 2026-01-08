//
//  ContinueWatchingSettingsView.swift
//  FlixorMac
//
//  Continue Watching display and caching settings
//

import SwiftUI

struct ContinueWatchingSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("continueWatchingLayout") private var layout: String = "landscape"
    @AppStorage("useCachedStreams") private var useCachedStreams: Bool = false
    @AppStorage("streamCacheTTL") private var cacheTTL: Int = 3600
    @State private var showPreview: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header with close button
            HStack {
                Text("Continue Watching")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Layout Section
                    SettingsSectionHeader(title: "Display Layout")
                    SettingsGroupCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Choose how continue watching items appear")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.top, 12)

                            HStack(spacing: 12) {
                                LayoutOptionButton(
                                    title: "Landscape",
                                    icon: "rectangle.fill",
                                    isSelected: layout == "landscape"
                                ) {
                                    layout = "landscape"
                                }

                                LayoutOptionButton(
                                    title: "Poster",
                                    icon: "rectangle.portrait.fill",
                                    isSelected: layout == "poster"
                                ) {
                                    layout = "poster"
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 12)
                        }
                    }

                    // Collapsible Preview Section
                    CollapsiblePreviewSection(title: "Preview", isExpanded: $showPreview) {
                        if layout == "landscape" {
                            landscapePreview
                        } else {
                            posterPreview
                        }
                    }

                    // Cache Section
                    SettingsSectionHeader(title: "Stream Caching")
                    SettingsGroupCard {
                        SettingsRow(icon: "arrow.triangle.2.circlepath.circle.fill", iconColor: .blue, title: "Cache Stream URLs", showDivider: !useCachedStreams) {
                            Toggle("", isOn: $useCachedStreams).labelsHidden()
                        }

                        if useCachedStreams {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Cache Duration")
                                    .font(.system(size: 12, weight: .medium))
                                    .padding(.horizontal, 12)

                                Picker("", selection: $cacheTTL) {
                                    Text("15 min").tag(900)
                                    Text("30 min").tag(1800)
                                    Text("1 hour").tag(3600)
                                    Text("6 hours").tag(21600)
                                    Text("12 hours").tag(43200)
                                    Text("24 hours").tag(86400)
                                }
                                .pickerStyle(.segmented)
                                .padding(.horizontal, 12)
                                .padding(.bottom, 12)
                            }
                        }
                    }

                    Text("Stream caching stores URLs locally for faster playback resume. Disable if you experience playback issues.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                .padding(24)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Previews

    private var landscapePreview: some View {
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

    private var posterPreview: some View {
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
