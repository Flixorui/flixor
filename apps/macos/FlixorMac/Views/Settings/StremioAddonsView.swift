//
//  StremioAddonsView.swift
//  FlixorMac
//
//  Native addon manager for Stremio manifests on macOS.
//

import AppKit
import SwiftUI

struct StremioAddonsView: View {
    @Environment(\.flixorTheme) private var theme
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
                VStack(alignment: .leading, spacing: DS.Space.s4) {
                    Text("Stremio Addons")
                        .font(.flixor(.title3, weight: .semibold))
                    Text("Install, reorder, configure, and remove Stremio addons.")
                        .font(.flixor(.footnote))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.flixorIcon(DS.Icon.lg))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DS.Space.s24)
            .padding(.top, DS.Space.s20)
            .padding(.bottom, DS.Space.s16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s24) {
                    SettingsSectionHeader(title: "Install")
                    SettingsGroupCard {
                        VStack(alignment: .leading, spacing: DS.Space.s12) {
                            TextField("https://example.com/manifest.json", text: $manifestURL)
                                .textFieldStyle(.plain)
                                .padding(DS.Space.s10)
                                .background(theme.settingsFieldBackground)
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r8, style: .continuous))

                            HStack {
                                Text("Paste a Stremio addon manifest URL. OpenSubtitles is installed automatically the first time Stremio is enabled.")
                                    .font(.flixor(.caption))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button(isInstalling ? "Installing..." : "Install Addon") {
                                    Task { await installAddon() }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(isInstalling || manifestURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                        .padding(DS.Space.s12)
                    }

                    if let lastInstallError, !lastInstallError.isEmpty {
                        SettingsSectionHeader(title: "Last Install Error")
                        SettingsGroupCard {
                            VStack(alignment: .leading, spacing: DS.Space.s8) {
                                Text(lastInstallError)
                                    .font(.flixor(.footnote, design: .monospaced))
                                    .foregroundStyle(.red)
                                    .textSelection(.enabled)
                                Text("The full error is also written to Settings > Logs.")
                                    .font(.flixor(.caption))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(DS.Space.s12)
                        }
                    }

                    SettingsSectionHeader(title: "Installed Addons")
                    if addonSummaries.isEmpty && !isLoading {
                        SettingsGroupCard {
                            VStack(spacing: DS.Space.s10) {
                                Image(systemName: "puzzlepiece.extension")
                                    .font(.flixor(.largeTitle))
                                    .foregroundStyle(.secondary)
                                Text("No addons installed")
                                    .font(.flixor(.callout, weight: .medium))
                                Text("Install a manifest URL to add Stremio stream or subtitle providers.")
                                    .font(.flixor(.caption))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DS.Space.s24)
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
                .padding(DS.Space.s24)
            }
        }
        .frame(width: 760, height: 720)
        .background(theme.settingsWindowBackground)
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
        VStack(alignment: .leading, spacing: DS.Space.s10) {
            HStack(alignment: .top, spacing: DS.Space.s12) {
                VStack(alignment: .leading, spacing: DS.Space.s4) {
                    Text(addon.name)
                        .font(.flixor(.body, weight: .semibold))
                    if let manifestURL = addon.manifestURL, !manifestURL.isEmpty {
                        Text(manifestURL)
                            .font(.flixor(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }
                }
                Spacer()
                HStack(spacing: DS.Space.s6) {
                    capabilityBadge(title: "Streams", active: addon.streamCapable, color: .blue)
                    capabilityBadge(title: "Subtitles", active: addon.subtitleCapable, color: .purple)
                    capabilityBadge(title: "Catalogs", active: addon.catalogCapable, color: .teal)
                }
            }

            if addon.configurationRequired {
                Label("This addon requires configuration before it can return results.", systemImage: "exclamationmark.triangle.fill")
                    .font(.flixor(.caption))
                    .foregroundStyle(.orange)
            }

            HStack(spacing: DS.Space.s8) {
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
        .padding(.vertical, DS.Space.s4)
    }

    private func capabilityBadge(title: String, active: Bool, color: Color) -> some View {
        Text(title)
            .font(.flixor(.micro, weight: .semibold))
            .foregroundStyle(active ? color : .secondary)
            .padding(.horizontal, DS.Space.s8)
            .padding(.vertical, DS.Space.s4)
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
