//
//  StremioAddonsView.swift
//  FlixorMac
//
//  Native addon manager for Stremio manifests on macOS.
//

import AppKit
import SwiftUI

struct StremioAddonsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var profileSettings = ProfileSettings.shared
    @State private var manifestURL = ""
    @State private var addonSummaries: [StremioAddonSummary] = []
    @State private var isLoading = false
    @State private var isInstalling = false
    @State private var lastInstallError: String?
    @State private var alertMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stremio Addons")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Install, reorder, configure, and remove Stremio addons.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SettingsSectionHeader(title: "Install")
                    SettingsGroupCard {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("https://example.com/manifest.json", text: $manifestURL)
                                .textFieldStyle(.plain)
                                .padding(10)
                                .background(Color(NSColor.textBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                            HStack {
                                Text("Paste a Stremio addon manifest URL. OpenSubtitles is installed automatically the first time Stremio is enabled.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button(isInstalling ? "Installing..." : "Install Addon") {
                                    Task { await installAddon() }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(isInstalling || manifestURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                        .padding(12)
                    }

                    if let lastInstallError, !lastInstallError.isEmpty {
                        SettingsSectionHeader(title: "Last Install Error")
                        SettingsGroupCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(lastInstallError)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.red)
                                    .textSelection(.enabled)
                                Text("The full error is also written to Settings > Logs.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                        }
                    }

                    SettingsSectionHeader(title: "Installed Addons")
                    if addonSummaries.isEmpty && !isLoading {
                        SettingsGroupCard {
                            VStack(spacing: 10) {
                                Image(systemName: "puzzlepiece.extension")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.secondary)
                                Text("No addons installed")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Install a manifest URL to add Stremio stream or subtitle providers.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                        }
                    } else {
                        List {
                            ForEach(addonSummaries) { addon in
                                addonRow(addon)
                                    .listRowBackground(Color.clear)
                            }
                            .onMove(perform: moveAddon)
                        }
                        .listStyle(.inset)
                        .frame(minHeight: 320)
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 760, height: 720)
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            await refresh()
        }
        .alert("Stremio Addons", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    @ViewBuilder
    private func addonRow(_ addon: StremioAddonSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(addon.name)
                        .font(.system(size: 14, weight: .semibold))
                    if let manifestURL = addon.manifestURL, !manifestURL.isEmpty {
                        Text(manifestURL)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }
                }
                Spacer()
                HStack(spacing: 6) {
                    capabilityBadge(title: "Streams", active: addon.streamCapable, color: .blue)
                    capabilityBadge(title: "Subtitles", active: addon.subtitleCapable, color: .purple)
                    capabilityBadge(title: "Catalogs", active: addon.catalogCapable, color: .teal)
                }
            }

            if addon.configurationRequired {
                Label("This addon requires configuration before it can return results.", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 8) {
                if addon.configureURL != nil {
                    Button("Configure") {
                        Task { await configureAddon(addon) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button("Uninstall", role: .destructive) {
                    Task { await removeAddon(addon) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
                    .help("Drag to reorder")
            }
        }
        .padding(.vertical, 4)
    }

    private func capabilityBadge(title: String, active: Bool, color: Color) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(active ? color : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((active ? color.opacity(0.14) : Color.white.opacity(0.06)), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(active ? color.opacity(0.35) : Color.white.opacity(0.08), lineWidth: 1)
            )
    }

    @MainActor
    private func refresh() async {
        isLoading = true
        await StremioService.shared.ensureInitialized(installDefaults: profileSettings.stremioPlaybackEnabled)
        addonSummaries = await StremioService.shared.getAddonSummary()
        isLoading = false
    }

    private func installAddon() async {
        let trimmed = manifestURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        await MainActor.run {
            isInstalling = true
            lastInstallError = nil
        }

        do {
            _ = try await StremioService.shared.installAddon(from: trimmed)
            await MainActor.run {
                manifestURL = ""
                alertMessage = "Addon installed successfully."
            }
            await refresh()
        } catch {
            let message = error.localizedDescription
            AppLogger.shared.error("[Stremio] Addon install failed from settings", data: [
                "manifestUrl": trimmed,
                "error": message,
            ])
            await MainActor.run {
                lastInstallError = message
                alertMessage = message
            }
        }

        await MainActor.run {
            isInstalling = false
        }
    }

    private func removeAddon(_ addon: StremioAddonSummary) async {
        await StremioService.shared.removeAddon(installationId: addon.installationId)
        await refresh()
    }

    private func configureAddon(_ addon: StremioAddonSummary) async {
        guard let urlString = addon.configureURL, let url = URL(string: urlString) else {
            return
        }
        await MainActor.run {
            _ = NSWorkspace.shared.open(url)
        }
    }

    private func moveAddon(from offsets: IndexSet, to destination: Int) {
        Task {
            await StremioService.shared.moveAddons(fromOffsets: offsets, toOffset: destination)
            await refresh()
        }
    }
}
