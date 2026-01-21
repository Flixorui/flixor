//
//  ProfileSelectView.swift
//  FlixorMac
//
//  Profile selection screen for Plex Home multi-profile support
//

import SwiftUI
import FlixorKit

struct ProfileSelectView: View {
    @StateObject private var profileManager = ProfileManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedUser: PlexHomeUser?
    @State private var showPinEntry = false
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var appearAnimation = false

    let onProfileSelected: (() -> Void)?

    init(onProfileSelected: (() -> Void)? = nil) {
        self.onProfileSelected = onProfileSelected
    }

    var body: some View {
        ZStack {
            // Background with subtle gradient
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.08),
                    Color(red: 0.02, green: 0.02, blue: 0.05)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Ambient glow effects
            GeometryReader { geo in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.purple.opacity(0.15), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: geo.size.width * 0.4
                        )
                    )
                    .frame(width: geo.size.width * 0.8)
                    .position(x: geo.size.width * 0.2, y: geo.size.height * 0.3)
                    .blur(radius: 60)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.blue.opacity(0.12), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: geo.size.width * 0.4
                        )
                    )
                    .frame(width: geo.size.width * 0.7)
                    .position(x: geo.size.width * 0.8, y: geo.size.height * 0.6)
                    .blur(radius: 60)
            }

            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 60)

                // Header
                VStack(spacing: 8) {
                    Text("Who's Watching?")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .white.opacity(0.85)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .opacity(appearAnimation ? 1 : 0)
                        .offset(y: appearAnimation ? 0 : -20)

                    Text("Select a profile to continue")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .opacity(appearAnimation ? 1 : 0)
                        .offset(y: appearAnimation ? 0 : -10)
                }
                .padding(.bottom, 48)

                // Profile Grid
                if profileManager.isLoading && profileManager.homeUsers.isEmpty {
                    loadingView
                } else if profileManager.homeUsers.isEmpty {
                    emptyStateView
                } else {
                    profileGrid
                }

                // Error message
                if let error = errorMessage {
                    errorView(error)
                }

                Spacer()

                // Cancel button
                if profileManager.activeProfile != nil || FlixorCore.shared.isPlexAuthenticated {
                    cancelButton
                }
            }
            .padding(.horizontal, 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showPinEntry) {
            if let user = selectedUser {
                PinEntryView(user: user) { pin in
                    Task {
                        await completeProfileSwitch(user: user, pin: pin)
                    }
                }
            }
        }
        .task {
            await profileManager.loadHomeUsers()
            withAnimation(.easeOut(duration: 0.6)) {
                appearAnimation = true
            }
        }
    }

    // MARK: - Subviews

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white.opacity(0.7))
            Text("Loading profiles...")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(60)
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 100, height: 100)
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 44))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Text("No profiles found")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(60)
    }

    private var profileGrid: some View {
        // Horizontal layout using HStack with wrapping for more than 5 profiles
        let users = profileManager.homeUsers
        let rows = users.chunked(into: 5)

        return VStack(spacing: 40) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, rowUsers in
                HStack(spacing: 48) {
                    ForEach(Array(rowUsers.enumerated()), id: \.element.id) { colIndex, user in
                        let index = rowIndex * 5 + colIndex
                        ProfileCard(
                            user: user,
                            isActive: isActiveProfile(user),
                            isProcessing: isProcessing && selectedUser?.id == user.id
                        ) {
                            handleProfileTap(user)
                        }
                        .opacity(appearAnimation ? 1 : 0)
                        .offset(y: appearAnimation ? 0 : 30)
                        .animation(
                            .spring(response: 0.6, dampingFraction: 0.8).delay(Double(index) * 0.08),
                            value: appearAnimation
                        )
                    }
                }
            }
        }
    }

    private func errorView(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.red)
            Text(error)
                .foregroundColor(.red.opacity(0.9))
        }
        .font(.system(size: 14, weight: .medium))
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color.red.opacity(0.15))
                .overlay(Capsule().strokeBorder(Color.red.opacity(0.3), lineWidth: 1))
        )
        .padding(.top, 24)
    }

    private var cancelButton: some View {
        Button(action: { dismiss() }) {
            Text("Cancel")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .padding(.bottom, 48)
        .opacity(appearAnimation ? 1 : 0)
    }

    // MARK: - Logic

    private func isActiveProfile(_ user: PlexHomeUser) -> Bool {
        if let active = profileManager.activeProfile {
            return active.uuid == user.uuid
        }
        return user.admin && profileManager.activeProfile == nil
    }

    private func handleProfileTap(_ user: PlexHomeUser) {
        guard !isProcessing else { return }

        if isActiveProfile(user) {
            dismiss()
            return
        }

        selectedUser = user

        if user.protected {
            showPinEntry = true
        } else {
            Task {
                await completeProfileSwitch(user: user, pin: nil)
            }
        }
    }

    private func completeProfileSwitch(user: PlexHomeUser, pin: String?) async {
        isProcessing = true
        errorMessage = nil
        showPinEntry = false

        do {
            if user.admin && profileManager.activeProfile != nil {
                try await profileManager.switchToMainAccount()
            } else {
                try await profileManager.switchProfile(user, pin: pin)
            }

            onProfileSelected?()
            dismiss()
        } catch {
            if error.localizedDescription.contains("Invalid PIN") {
                errorMessage = "Invalid PIN. Please try again."
                if user.protected {
                    showPinEntry = true
                }
            } else {
                errorMessage = error.localizedDescription
            }
        }

        isProcessing = false
    }
}

// MARK: - Profile Card

struct ProfileCard: View {
    let user: PlexHomeUser
    let isActive: Bool
    let isProcessing: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    // Premium color palette with gradients
    private let gradientSets: [(Color, Color)] = [
        (Color(hex: "FF6B6B"), Color(hex: "C44569")),  // Coral Rose
        (Color(hex: "4ECDC4"), Color(hex: "2C7873")),  // Teal
        (Color(hex: "A8E6CF"), Color(hex: "56AB91")),  // Mint
        (Color(hex: "DDA0DD"), Color(hex: "9B59B6")),  // Lavender
        (Color(hex: "FFD93D"), Color(hex: "F39C12")),  // Golden
        (Color(hex: "6C5CE7"), Color(hex: "4834D4")),  // Purple
        (Color(hex: "74B9FF"), Color(hex: "0984E3")),  // Sky Blue
        (Color(hex: "FD79A8"), Color(hex: "E84393")),  // Pink
    ]

    private var gradientColors: (Color, Color) {
        let index = abs(user.id) % gradientSets.count
        return gradientSets[index]
    }

    private let avatarSize: CGFloat = 120
    private let cardWidth: CGFloat = 140
    private let cardHeight: CGFloat = 190

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                // Avatar container with glow - fixed size
                ZStack {
                    // Glow effect for active/hovered state
                    Circle()
                        .fill(gradientColors.0.opacity(isActive || isHovered ? 0.4 : 0))
                        .frame(width: avatarSize + 20, height: avatarSize + 20)
                        .blur(radius: 20)

                    // Avatar with border ring
                    ZStack {
                        // Ring border
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: isActive
                                        ? [.white, .white.opacity(0.7)]
                                        : (isHovered ? [.white.opacity(0.5), .white.opacity(0.3)] : [.clear]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: isActive ? 3 : 2
                            )
                            .frame(width: avatarSize + 8, height: avatarSize + 8)

                        // Avatar image or initials
                        ProfileAvatarView(user: user, size: avatarSize)
                            .shadow(color: .black.opacity(0.3), radius: 10, y: 5)

                        // Processing overlay
                        if isProcessing {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: avatarSize, height: avatarSize)
                            ProgressView()
                                .scaleEffect(1.2)
                                .tint(.white)
                        }
                    }
                    .scaleEffect(isHovered ? 1.08 : 1.0)

                    // Badges overlay
                    badgesOverlay
                        .scaleEffect(isHovered ? 1.08 : 1.0)
                }
                .frame(width: avatarSize + 24, height: avatarSize + 24)

                // Name and subtitle - fixed height
                VStack(spacing: 2) {
                    Text(user.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(isHovered || isActive ? .white : .white.opacity(0.8))
                        .lineLimit(1)

                    Text(user.admin ? "Account Owner" : " ")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(user.admin ? 0.4 : 0))
                }
                .frame(height: 36)
            }
            .frame(width: cardWidth, height: cardHeight)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var badgesOverlay: some View {
        ZStack {
            // Lock badge (top right)
            if user.protected {
                VStack {
                    HStack {
                        Spacer()
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 26, height: 26)
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.2), Color.white.opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 26, height: 26)
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white.opacity(0.9))
                        }
                        .offset(x: 2, y: -2)
                    }
                    Spacer()
                }
            }

            // Kids badge (bottom)
            if user.restricted {
                VStack {
                    Spacer()
                    Text("KIDS")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "00B4D8"), Color(hex: "0077B6")],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                        .shadow(color: Color(hex: "00B4D8").opacity(0.5), radius: 6, y: 2)
                        .offset(y: 6)
                }
            }
        }
        .frame(width: avatarSize + 8, height: avatarSize + 8)
    }
}

// MARK: - Array Extension for Chunking

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

#if DEBUG
struct ProfileSelectView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileSelectView()
    }
}
#endif
