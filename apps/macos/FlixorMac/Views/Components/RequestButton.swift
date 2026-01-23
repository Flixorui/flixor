//
//  RequestButton.swift
//  FlixorMac
//
//  Button to request media through Overseerr
//

import SwiftUI

// MARK: - Overseerr Icon

struct OverseerrIcon: View {
    var size: CGFloat = 18

    private let gradient = LinearGradient(
        colors: [Color(hex: "C395FC"), Color(hex: "4F65F5")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        ZStack {
            // Outer filled circle
            Circle()
                .fill(gradient)
                .frame(width: size, height: size)

            // Inner cutout ring (creates the donut effect)
            Circle()
                .fill(Color.black.opacity(0.85))
                .frame(width: size * 0.58, height: size * 0.58)
                .offset(x: size * 0.042, y: size * 0.042)

            // Small inner circle (the dot in the center-left)
            Circle()
                .fill(gradient)
                .frame(width: size * 0.29, height: size * 0.29)
                .offset(x: -size * 0.104, y: -size * 0.104)
        }
    }
}

struct RequestButton: View {
    enum Style {
        case icon
        case pill
        case circle  // Apple TV+ style large circle
    }

    let tmdbId: Int
    let mediaType: String // "movie" or "tv"
    let title: String
    var style: Style = .pill

    @State private var status: OverseerrMediaStatus?
    @State private var isLoading = false
    @State private var isRequesting = false
    @State private var showConfirmation = false
    @State private var showSeasonPicker = false
    @State private var selectedSeasons: Set<Int> = []

    @ObservedObject private var profileSettings = ProfileSettings.shared

    // Only show if Overseerr is enabled and configured
    private var shouldShow: Bool {
        return OverseerrService.shared.isReady()
    }

    /// Check if this is a partially available TV show with unavailable seasons
    private var isPartiallyAvailableTv: Bool {
        status?.isPartiallyAvailableTv ?? false
    }

    /// Get requestable seasons for partially available TV shows
    private var requestableSeasons: [OverseerrSeason] {
        status?.requestableSeasons ?? []
    }

    /// Get all seasons (excluding season 0) for the season picker
    private var allSeasons: [OverseerrSeason] {
        (status?.seasons ?? []).filter { $0.seasonNumber > 0 }
    }

    /// Check if there are any requestable seasons
    private var hasRequestableSeasons: Bool {
        !requestableSeasons.isEmpty
    }

    var body: some View {
        Group {
            if shouldShow {
                switch style {
                case .icon:
                    iconButton
                case .pill:
                    pillButton
                case .circle:
                    circleButton
                }
            }
        }
        .task(id: tmdbId) {
            // Reset status and reload when tmdbId changes (navigation to new item)
            status = nil
            selectedSeasons = []
            await loadStatus()
        }
        .alert("Request \(title)?", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Request") {
                Task { await requestMedia() }
            }
        } message: {
            Text("This will submit a request to Overseerr. You'll be notified when it becomes available.")
        }
        .sheet(isPresented: $showSeasonPicker) {
            SeasonPickerSheet(
                title: title,
                seasons: allSeasons,
                hasRequestableSeasons: hasRequestableSeasons,
                selectedSeasons: $selectedSeasons,
                isRequesting: $isRequesting,
                onRequest: {
                    Task { await requestSelectedSeasons() }
                }
            )
        }
    }

    private var currentStatus: OverseerrStatus {
        status?.status ?? .unknown
    }

    private var canRequest: Bool {
        status?.canRequest ?? false
    }

    private var buttonColor: Color {
        switch currentStatus {
        case .notRequested, .unknown:
            return Color(hex: "6366F1") // Indigo
        case .pending:
            return Color.orange
        case .approved:
            return Color.green
        case .declined:
            return Color.red
        case .processing:
            return Color.blue
        case .partiallyAvailable:
            return Color.orange
        case .available:
            return Color.green
        }
    }

    private var buttonLabel: String {
        switch currentStatus {
        case .notRequested:
            return "Request"
        case .pending:
            return "Pending"
        case .approved:
            return "Approved"
        case .declined:
            return "Declined"
        case .processing:
            return "Processing"
        case .partiallyAvailable:
            return "Partial"
        case .available:
            return "Available"
        case .unknown:
            return "Request"
        }
    }

    private var buttonIcon: String {
        switch currentStatus {
        case .notRequested, .unknown:
            return "arrow.down.circle"
        case .pending:
            return "clock"
        case .approved:
            return "checkmark.circle"
        case .declined:
            return "xmark.circle"
        case .processing:
            return "arrow.clockwise"
        case .partiallyAvailable:
            return "circle.lefthalf.filled"
        case .available:
            return "checkmark.circle.fill"
        }
    }

    private var pillButton: some View {
        Button {
            if canRequest {
                if isPartiallyAvailableTv {
                    // Show season picker for partially available TV shows
                    showSeasonPicker = true
                } else {
                    showConfirmation = true
                }
            }
        } label: {
            HStack(spacing: 8) {
                if isLoading || isRequesting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                } else if canRequest {
                    // Show Overseerr icon for requestable states
                    OverseerrIcon(size: 18)
                } else {
                    Image(systemName: buttonIcon)
                        .font(.system(size: 14, weight: .bold))
                }
                Text(buttonLabel)
                    .font(.system(size: 15, weight: .semibold))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(buttonColor.opacity(canRequest ? 0.9 : 0.4))
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(isLoading || isRequesting || !canRequest)
    }

    private var iconButton: some View {
        Button {
            if canRequest {
                if isPartiallyAvailableTv {
                    showSeasonPicker = true
                } else {
                    showConfirmation = true
                }
            }
        } label: {
            Group {
                if isLoading || isRequesting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.mini)
                } else if canRequest {
                    OverseerrIcon(size: 20)
                } else {
                    Image(systemName: buttonIcon)
                        .font(.system(size: 14, weight: .bold))
                }
            }
            .frame(width: 32, height: 32)
            .background(canRequest ? Color.clear : buttonColor.opacity(0.4))
            .foregroundStyle(.white)
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading || isRequesting || !canRequest)
    }

    // Apple TV+ style large circle button
    private var circleButton: some View {
        Button {
            if canRequest {
                if isPartiallyAvailableTv {
                    showSeasonPicker = true
                } else {
                    showConfirmation = true
                }
            }
        } label: {
            Group {
                if isLoading || isRequesting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                } else if canRequest {
                    OverseerrIcon(size: 24)
                } else {
                    Image(systemName: buttonIcon)
                        .font(.system(size: 20, weight: .medium))
                }
            }
            .frame(width: 44, height: 44)
            .background(canRequest ? buttonColor.opacity(0.6) : buttonColor.opacity(0.3))
            .foregroundStyle(.white)
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading || isRequesting || !canRequest)
        .help(canRequest ? "Request via Overseerr" : buttonLabel)
    }

    @MainActor
    private func loadStatus() async {
        guard shouldShow else { return }

        isLoading = true
        defer { isLoading = false }

        status = await OverseerrService.shared.getMediaStatus(tmdbId: tmdbId, mediaType: mediaType)
    }

    @MainActor
    private func requestMedia() async {
        guard canRequest else { return }

        isRequesting = true
        defer { isRequesting = false }

        let result = await OverseerrService.shared.requestMedia(tmdbId: tmdbId, mediaType: mediaType)

        if result.success {
            // Update status after successful request
            if let newStatus = result.status {
                status = OverseerrMediaStatus(status: newStatus, requestId: result.requestId, canRequest: false)
            } else {
                // Reload status from server
                await loadStatus()
            }
        }
    }

    @MainActor
    private func requestSelectedSeasons() async {
        guard canRequest, !selectedSeasons.isEmpty else { return }

        isRequesting = true
        defer { isRequesting = false }

        let seasonsArray = Array(selectedSeasons).sorted()
        let result = await OverseerrService.shared.requestMedia(
            tmdbId: tmdbId,
            mediaType: mediaType,
            seasons: seasonsArray
        )

        if result.success {
            showSeasonPicker = false
            selectedSeasons = []
            // Reload status from server to get updated season availability
            await loadStatus()
        }
    }
}

// MARK: - Season Picker Sheet

private struct SeasonPickerSheet: View {
    let title: String
    let seasons: [OverseerrSeason]
    let hasRequestableSeasons: Bool
    @Binding var selectedSeasons: Set<Int>
    @Binding var isRequesting: Bool
    let onRequest: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Request Seasons")
                        .font(.system(size: 18, weight: .semibold))
                    Text(title)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            // Warning message if no requestable seasons
            if !hasRequestableSeasons {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.yellow)

                    Text("All unavailable seasons have some episodes already downloaded. Overseerr cannot request the remaining episodes for partially downloaded seasons.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .background(Color.yellow.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }

            // Season list
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(seasons.sorted(by: { $0.seasonNumber < $1.seasonNumber }), id: \.seasonNumber) { season in
                        SeasonRow(
                            season: season,
                            isSelected: selectedSeasons.contains(season.seasonNumber),
                            onToggle: {
                                guard season.canRequest else { return }
                                if selectedSeasons.contains(season.seasonNumber) {
                                    selectedSeasons.remove(season.seasonNumber)
                                } else {
                                    selectedSeasons.insert(season.seasonNumber)
                                }
                            }
                        )
                    }
                }
                .padding(20)
            }

            Divider()

            // Footer with actions
            HStack {
                if hasRequestableSeasons {
                    Button("Select All") {
                        // Only select requestable seasons
                        selectedSeasons = Set(seasons.filter { $0.canRequest }.map { $0.seasonNumber })
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                }

                Spacer()

                Button(hasRequestableSeasons ? "Cancel" : "Close") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                if hasRequestableSeasons {
                    Button {
                        onRequest()
                    } label: {
                        HStack(spacing: 6) {
                            if isRequesting {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .controlSize(.small)
                            }
                            Text("Request \(selectedSeasons.count) Season\(selectedSeasons.count == 1 ? "" : "s")")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedSeasons.isEmpty ? Color.gray.opacity(0.3) : Color(hex: "6366F1"))
                        )
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedSeasons.isEmpty || isRequesting)
                }
            }
            .padding(20)
        }
        .frame(width: 400, height: 550)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SeasonRow: View {
    let season: OverseerrSeason
    let isSelected: Bool
    let onToggle: () -> Void

    private var isRequestable: Bool {
        season.canRequest
    }

    private var statusText: String {
        if season.isAvailable {
            return "Available"
        } else if season.isProcessing {
            return "Processing"
        } else if season.isPending {
            return "Pending"
        } else if season.isPartiallyAvailable {
            return "Partial"
        }
        return "Not Available"
    }

    private var statusColor: Color {
        if season.isAvailable {
            return .green
        } else if season.isProcessing || season.isPending {
            return .orange
        } else if season.isPartiallyAvailable {
            return .yellow
        }
        return .secondary
    }

    private var iconName: String {
        if season.isAvailable {
            return "checkmark.circle.fill"
        } else if season.isPartiallyAvailable {
            return "exclamationmark.circle.fill"
        } else if isSelected {
            return "checkmark.circle.fill"
        } else {
            return "circle"
        }
    }

    private var iconColor: Color {
        if season.isAvailable {
            return .green
        } else if season.isPartiallyAvailable {
            return .yellow
        } else if isSelected {
            return Color(hex: "6366F1")
        } else {
            return .secondary
        }
    }

    var body: some View {
        Button {
            if isRequestable {
                onToggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: iconName)
                        .font(.system(size: 20))
                        .foregroundStyle(iconColor)

                    Text("Season \(season.seasonNumber)")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isRequestable ? .primary : .secondary)

                    Spacer()

                    Text(statusText)
                        .font(.system(size: 13, weight: season.isAvailable ? .semibold : .regular))
                        .foregroundStyle(statusColor)
                }

                // Show message for partially available seasons
                if season.isPartiallyAvailable {
                    Text("Some episodes available - Overseerr cannot request remaining")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 28)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected && isRequestable ? Color(hex: "6366F1").opacity(0.15) : Color.secondary.opacity(0.1))
            )
            .opacity(isRequestable ? 1.0 : 0.6)
        }
        .buttonStyle(.plain)
        .disabled(!isRequestable)
    }
}
