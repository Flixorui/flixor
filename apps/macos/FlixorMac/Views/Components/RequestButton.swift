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

    @AppStorage("overseerrEnabled") private var overseerrEnabled: Bool = false

    // Only show if Overseerr is enabled and configured
    private var shouldShow: Bool {
        return OverseerrService.shared.isReady()
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
        .task {
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
                showConfirmation = true
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
                showConfirmation = true
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
                showConfirmation = true
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
}
