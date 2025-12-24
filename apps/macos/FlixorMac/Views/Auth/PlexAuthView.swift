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

            VStack(spacing: 40) {
                Spacer()

                // Logo
                VStack(spacing: 12) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.white)

                    Text("FLIXOR")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                Spacer()

                // Sign in button
                VStack(spacing: 20) {
                    Button(action: {
                        Task {
                            await viewModel.startAuthentication()
                        }
                    }) {
                        HStack(spacing: 12) {
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
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isAuthenticating)

                    Text("A browser window will open to\nauthenticate with Plex.tv")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)

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
