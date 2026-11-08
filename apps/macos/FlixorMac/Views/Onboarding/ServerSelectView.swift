//
//  ServerSelectView.swift
//  FlixorMac
//
//  Server selection screen during onboarding
//

import SwiftUI
import FlixorKit

struct ServerSelectView: View {
    @Environment(\.flixorTheme) private var theme
    let onServerSelected: (PlexServerResource) -> Void

    @State private var servers: [PlexServerResource] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            // Animated gradient background
            if !theme.pureBlack {
                AnimatedGradientBackground()
            }

            VStack(spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: DS.Space.s8) {
                    Text("Select Your Server")
                        .font(.system(size: 36, weight: .heavy))
                        .foregroundColor(.white)

                    Text("Choose a Plex server to connect to")
                        .font(.flixor(.bodyLarge))
                        .foregroundColor(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Space.s60)
                .padding(.top, DS.Space.s60)
                .padding(.bottom, DS.Space.s40)

                // Content
                if isLoading {
                    loadingState
                } else if let error = errorMessage {
                    errorState(message: error)
                } else if servers.isEmpty {
                    emptyState
                } else {
                    serverList
                }

                Spacer()

                // Refresh button
                Button {
                    Task { await loadServers() }
                } label: {
                    HStack(spacing: DS.Space.s8) {
                        Image(systemName: "arrow.clockwise")
                            .font(.flixorIcon(DS.Icon.sm, weight: .semibold))
                        Text("Refresh Servers")
                            .font(.flixor(.body, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, DS.Space.s20)
                    .padding(.vertical, DS.Space.s12)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(DS.Radius.r10)
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                .padding(.bottom, DS.Space.s40)
            }
        }
        .task {
            await loadServers()
        }
    }

    private var loadingState: some View {
        VStack(spacing: DS.Space.s16) {
            ProgressView()
                .scaleEffect(1.5)
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
            Text("Loading servers...")
                .font(.flixor(.body))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: DS.Space.s16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.flixorIcon(DS.Icon.huge))
                .foregroundColor(.orange)

            Text("Error Loading Servers")
                .font(.flixor(.title3, weight: .semibold))
                .foregroundColor(.white)

            Text(message)
                .font(.flixor(.body))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.Space.s40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: DS.Space.s16) {
            Image(systemName: "server.rack")
                .font(.flixorIcon(DS.Icon.huge))
                .foregroundColor(.white.opacity(0.3))

            Text("No Servers Found")
                .font(.flixor(.title3, weight: .semibold))
                .foregroundColor(.white)

            Text("Make sure you have at least one Plex Media Server\nset up and linked to your account.")
                .font(.flixor(.body))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var serverList: some View {
        ScrollView {
            VStack(spacing: DS.Space.s12) {
                ForEach(servers) { server in
                    ServerRow(server: server) {
                        onServerSelected(server)
                    }
                }
            }
            .padding(.horizontal, DS.Space.s60)
        }
    }

    @MainActor
    private func loadServers() async {
        isLoading = true
        errorMessage = nil

        do {
            servers = try await FlixorCore.shared.getPlexServers()
            print("✅ [ServerSelect] Loaded \(servers.count) servers")
        } catch {
            print("❌ [ServerSelect] Failed to load servers: \(error)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

// MARK: - Server Row

private struct ServerRow: View {
    let server: PlexServerResource
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DS.Space.s16) {
                // Server icon
                ZStack {
                    RoundedRectangle(cornerRadius: DS.Radius.r12)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 48, height: 48)

                    Image(systemName: server.owned == true ? "server.rack" : "cloud")
                        .font(.flixorIcon(DS.Icon.lg))
                        .foregroundColor(server.presence == true ? .green : .orange)
                }

                // Server info
                VStack(alignment: .leading, spacing: DS.Space.s4) {
                    Text(server.name)
                        .font(.flixor(.headline, weight: .semibold))
                        .foregroundColor(.white)

                    HStack(spacing: DS.Space.s6) {
                        // Online status
                        Circle()
                            .fill(server.presence == true ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)

                        Text(server.presence == true ? "Online" : "Offline")
                            .font(.flixor(.footnote))
                            .foregroundColor(.white.opacity(0.5))

                        Text("·")
                            .foregroundColor(.white.opacity(0.3))

                        Text(server.owned == true ? "Owned" : "Shared")
                            .font(.flixor(.footnote))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }

                Spacer()

                // Arrow
                Image(systemName: "chevron.right")
                    .font(.flixorIcon(DS.Icon.sm, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(DS.Space.s16)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.r16)
                    .fill(Color.white.opacity(isHovered ? 0.12 : 0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.r16)
                            .stroke(Color.white.opacity(isHovered ? 0.15 : 0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Animated Gradient Background (reuse from OnboardingView)

private struct AnimatedGradientBackground: View {
    @State private var animateGradient = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: "#1a1a2e"),
                    Color(hex: "#16213e"),
                    Color(hex: "#0f0f23")
                ],
                startPoint: animateGradient ? .topLeading : .bottomTrailing,
                endPoint: animateGradient ? .bottomTrailing : .topLeading
            )

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
    ServerSelectView { server in
        print("Selected: \(server.name)")
    }
    .frame(width: 900, height: 700)
}
#endif
