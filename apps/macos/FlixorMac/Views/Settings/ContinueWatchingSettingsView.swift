//
//  ContinueWatchingSettingsView.swift
//  FlixorMac
//
//  Continue Watching display and caching settings
//

import SwiftUI

struct ContinueWatchingSettingsView: View {
    @AppStorage("continueWatchingLayout") private var layout: String = "landscape"
    @AppStorage("useCachedStreams") private var useCachedStreams: Bool = false
    @AppStorage("streamCacheTTL") private var cacheTTL: Int = 3600

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            headerSection
            layoutSection
            cacheSection
            previewSection
        }
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Continue Watching")
                    .font(.headline)
                Text("Customize how your watch progress is displayed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var layoutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Display Layout")
                .font(.headline)

            HStack(spacing: 12) {
                layoutOption(
                    title: "Landscape",
                    icon: "rectangle.fill",
                    description: "16:9 thumbnails with progress bar",
                    value: "landscape"
                )

                layoutOption(
                    title: "Poster",
                    icon: "rectangle.portrait.fill",
                    description: "Portrait posters with progress ring",
                    value: "poster"
                )
            }

            Text("Choose how continue watching items appear on your home screen.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(18)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func layoutOption(title: String, icon: String, description: String, value: String) -> some View {
        let isSelected = layout == value

        return Button(action: { layout = value }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 24))
                        .foregroundStyle(isSelected ? .blue : .secondary)

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.blue)
                    }
                }

                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Color.blue.opacity(0.15) : Color.white.opacity(0.03),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Color.blue.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var cacheSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stream Caching")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                Toggle("Cache Stream URLs", isOn: $useCachedStreams)

                Text("Store stream URLs locally for faster playback resume. Disable if you experience playback issues.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 20)
            }

            if useCachedStreams {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Cache Duration")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Picker("Cache TTL", selection: $cacheTTL) {
                        Text("15 minutes").tag(900)
                        Text("30 minutes").tag(1800)
                        Text("1 hour").tag(3600)
                        Text("6 hours").tag(21600)
                        Text("12 hours").tag(43200)
                        Text("24 hours").tag(86400)
                    }
                    .pickerStyle(.segmented)

                    Text("How long to keep cached stream URLs before refreshing. Shorter times are more reliable but slower to resume.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preview")
                .font(.headline)

            if layout == "landscape" {
                landscapePreview
            } else {
                posterPreview
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

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
                            .font(.system(size: 28))
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
                .frame(width: 140)
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
                            .frame(width: 36, height: 36)

                        Circle()
                            .trim(from: 0, to: CGFloat([0.3, 0.65, 0.45, 0.8][index]))
                            .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .frame(width: 36, height: 36)
                            .rotationEffect(.degrees(-90))

                        Image(systemName: "play.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                    }

                    Text(["Breaking Bad", "The Office", "Stranger Things", "Dark"][index])
                        .font(.caption2)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
                .frame(width: 80)
            }
        }
    }
}
