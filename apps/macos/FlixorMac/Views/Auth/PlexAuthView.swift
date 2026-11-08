//
//  PlexAuthView.swift
//  FlixorMac
//
//  Plex authentication screen
//

import SwiftUI

struct PlexAuthView: View {
    @StateObject private var viewModel = PlexAuthViewModel()
    @EnvironmentObject var sessionManager: SessionManager
    @ObservedObject private var appMode = AppModeStore.shared

    var body: some View {
        ZStack {
            // Background gradient matching web app
            LinearGradient(
                stops: [
                    .init(color: Color.backgroundPrimary, location: 0),
                    .init(color: Color.backgroundSecondary, location: 0.5),
                    .init(color: Color.backgroundPrimary, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: DS.Space.s40) {
                Spacer()

                // Logo
                VStack(spacing: DS.Space.s12) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.white)

                    Text("FLIXOR")
                        .font(.flixor(.displayLarge, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                Spacer()

                // Sign in button
                VStack(spacing: DS.Space.s20) {
                    Button(action: {
                        Task {
                            await viewModel.startAuthentication()
                        }
                    }) {
                        HStack(spacing: DS.Space.s12) {
                            if viewModel.isAuthenticating {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.white)
                            }

                            Text(viewModel.isAuthenticating ? "Authenticating..." : "Sign in with Plex")
                                .font(.headline)
                        }
                        .frame(maxWidth: 300)
                        .padding()
                        .background(Color.brand)
                        .foregroundStyle(.white)
                        .cornerRadius(DS.Radius.r8)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isAuthenticating)

                    Text("A browser window will open to\nauthenticate with Plex.tv")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)

                    // Standalone Stremio path - no Plex account needed.
                    VStack(spacing: DS.Space.s8) {
                        Divider()
                            .frame(maxWidth: 300)
                            .overlay(Color.white.opacity(0.15))

                        Button(action: {
                            appMode.select(.stremio)
                        }) {
                            Text("Continue without Plex")
                                .font(.headline)
                                .frame(maxWidth: 300)
                                .padding()
                                .background(Color.white.opacity(0.12))
                                .foregroundStyle(.white)
                                .cornerRadius(DS.Radius.r8)
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isAuthenticating)

                        Text("Use Flixor as a standalone Stremio app.\nYou can connect Plex later in Settings.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, DS.Space.s12)

                    if let error = viewModel.error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onReceive(viewModel.$authToken) { token in
            if let token = token {
                appMode.select(.plex)
                Task {
                    try? await sessionManager.login(token: token)
                }
            }
        }
    }
}

#if DEBUG
struct PlexAuthView_Previews: PreviewProvider {
    static var previews: some View {
        PlexAuthView()
            .environmentObject(SessionManager.shared)
            .frame(width: 800, height: 600)
    }
}
#endif
