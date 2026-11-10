//
//  LiveTVSettingsView.swift
//  FlixorMac
//
//  Personal build only (FLIXOR_LIVE_TV). Settings > Live TV and the first-run
//  setup sheet: the Live TV switch, the Xtream account, the xtream-web guide
//  server and the curated lineup file.
//

#if FLIXOR_LIVE_TV
import SwiftUI
import AppKit

/// Shared form used by Settings and by the setup sheet.
struct LiveTVSettingsForm: View {
    @ObservedObject private var store = LiveTVStore.shared
    @Environment(\.flixorTheme) private var theme
    var compact = false
    var onSaved: (() -> Void)?

    @State private var name = ""
    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var guideURL = ""
    @State private var guidePassword = ""
    @State private var accountMessage: (String, Bool)?
    @State private var guideMessage: (String, Bool)?
    @State private var testingAccount = false
    @State private var testingGuide = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            if !compact {
                SettingsGroupCard {
                    SettingsRow(title: "Show Live TV in Flixor", subtitle: "Adds Live TV to the navigation") {
                        Toggle("", isOn: $store.featureEnabled).labelsHidden()
                    }
                    SettingsRow(title: "Open Flixor in Live TV", showDivider: false) {
                        Toggle("", isOn: $store.openOnLaunch)
                            .labelsHidden()
                            .disabled(!store.featureEnabled)
                    }
                }
            }

            SettingsSectionHeader(title: "Xtream Account")
            SettingsGroupCard {
                fieldRow("Name", text: $name, prompt: "My IPTV")
                fieldRow("Server", text: $serverURL, prompt: "http://provider.example:8080")
                fieldRow("Username", text: $username, prompt: "")
                fieldRow("Password", text: $password, prompt: "", secure: true)
                buttonRow(message: accountMessage) {
                    if store.account != nil {
                        Button("Remove") {
                            store.saveAccount(nil)
                            loadFields()
                            accountMessage = ("Account removed.", true)
                        }
                        .buttonStyle(.settingsDestructive)
                    }
                    Button(testingAccount ? "Testing…" : "Test Connection") {
                        Task { await testAccount() }
                    }
                    .buttonStyle(.settingsSecondary)
                    .disabled(testingAccount || draftAccount == nil)
                }
            }
            SettingsFootnote("Saved in your Keychain. Flixor talks to the provider directly.")

            SettingsSectionHeader(title: "Guide Server (xtream-web)")
            SettingsGroupCard {
                fieldRow("Address", text: $guideURL, prompt: "https://tv.example.app")
                fieldRow("Password", text: $guidePassword, prompt: "", secure: true)
                buttonRow(message: guideMessage) {
                    if store.guideServer != nil {
                        Button("Remove") {
                            store.saveGuideServer(nil)
                            loadFields()
                            guideMessage = ("Guide server removed. The provider guide is used.", true)
                        }
                        .buttonStyle(.settingsDestructive)
                    }
                    Button(testingGuide ? "Signing in…" : "Test Sign-In") {
                        Task { await testGuide() }
                    }
                    .buttonStyle(.settingsSecondary)
                    .disabled(testingGuide || draftGuide == nil)
                }
            }
            SettingsFootnote("YouTube TV, India and premium schedules from your xtream-web server, with the provider guide as fallback.")

            SettingsSectionHeader(title: "Curated Lineup")
            SettingsGroupCard {
                lineupStatus
            }

            HStack {
                Spacer()
                Button(compact ? "Save and Open Live TV" : "Save") { save() }
                    .buttonStyle(.settingsPrimary)
                    .disabled(draftAccount == nil)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear(perform: loadFields)
    }

    // MARK: Drafts

    private var draftAccount: LiveTVAccount? {
        let a = LiveTVAccount(name: name.trimmingCharacters(in: .whitespaces), serverURL: serverURL.trimmingCharacters(in: .whitespacesAndNewlines),
                              username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
        return a.isComplete ? a : nil
    }

    private var draftGuide: LiveTVGuideServer? {
        let g = LiveTVGuideServer(url: guideURL.trimmingCharacters(in: .whitespacesAndNewlines), password: guidePassword)
        return g.isComplete ? g : nil
    }

    private func loadFields() {
        name = store.account?.name ?? ""
        serverURL = store.account?.serverURL ?? ""
        username = store.account?.username ?? ""
        password = store.account?.password ?? ""
        guideURL = store.guideServer?.url ?? ""
        guidePassword = store.guideServer?.password ?? ""
    }

    private func save() {
        guard let account = draftAccount else { return }
        store.saveAccount(account)
        let guide = draftGuide
        if guide != store.guideServer { store.saveGuideServer(guide) }
        accountMessage = ("Saved.", true)
        if store.isActive { store.loadCatalog(force: false) }
        onSaved?()
    }

    private func testAccount() async {
        guard let account = draftAccount else { return }
        testingAccount = true
        defer { testingAccount = false }
        do {
            let status = try await XtreamClient(account: account).authenticate()
            var parts = ["Connected", status.status]
            if let expiry = status.expiresAt { parts.append("expires \(expiry.formatted(date: .abbreviated, time: .omitted))") }
            if let max = status.maxConnections { parts.append("\(status.activeConnections ?? 0) of \(max) connections in use") }
            accountMessage = (parts.joined(separator: " · "), true)
        } catch {
            accountMessage = (LiveTVRedactor.redact(error.localizedDescription, account: account), false)
        }
    }

    private func testGuide() async {
        guard let guide = draftGuide else { return }
        testingGuide = true
        defer { testingGuide = false }
        do {
            // A test sign-in stores the new session; saving keeps it only if unchanged.
            if guide != store.guideServer { store.saveGuideServer(guide) }
            let client = XtreamWebGuideClient(server: guide)
            try await client.signIn()
            let sample = store.lineup.first.map { [$0.id] } ?? []
            if !sample.isEmpty, let entry = try await client.guide(ids: sample)[sample[0]] {
                guideMessage = ("Signed in · \(entry.source ?? "guide reachable")", true)
            } else {
                guideMessage = ("Signed in.", true)
            }
        } catch {
            guideMessage = (error.localizedDescription, false)
        }
    }

    // MARK: Lineup file

    @ViewBuilder
    private var lineupStatus: some View {
        let url = LiveTVStore.rulesURL
        let rules = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(CuratedLineupRules.self, from: $0) }
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            if let rules {
                Text("Exported from xtream-web on \(rules.generatedAt.prefix(10))")
                    .font(.system(size: 13))
                Text("\(rules.referenceLineup.count) US reference channels, \(rules.indianFeeds.count) Indian channels, \(rules.verifiedSources.count) verified sources")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
                if !store.lineup.isEmpty {
                    Text("Matched on your provider: \(store.lineup.filter { $0.market == .us }.count) US and \(store.lineup.filter { $0.market == .india }.count) Indian channels")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
            } else {
                Text("Lineup file not found")
                    .font(.system(size: 13))
                Text("Run the xtream-web lineup export on this Mac. It writes ~/Library/Application Support/Flixor/LiveTV/curated-lineup.json.")
                    .font(.system(size: 11.5)).foregroundStyle(theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Space.s12)
        .padding(.vertical, DS.Space.s10)
        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.horizontal, DS.Space.s12)
        HStack(spacing: DS.Space.s8) {
            Spacer()
            if store.isConfigured {
                Button("Reload Channels") { store.loadCatalog(force: true) }
                    .buttonStyle(.settingsSecondary)
            }
            Button("Show in Finder") {
                try? FileManager.default.createDirectory(at: LiveTVStore.supportDirectory, withIntermediateDirectories: true)
                NSWorkspace.shared.activateFileViewerSelecting([rules != nil ? url : LiveTVStore.supportDirectory])
            }
            .buttonStyle(.settingsSecondary)
        }
        .padding(.horizontal, DS.Space.s12)
        .padding(.vertical, DS.Space.s8)
    }

    // MARK: Pieces

    private func fieldRow(_ label: String, text: Binding<String>, prompt: String, secure: Bool = false) -> some View {
        SettingsRow(title: LocalizedStringKey(label)) {
            Group {
                if secure {
                    SecureField(prompt, text: text)
                } else {
                    TextField(prompt, text: text).disableAutocorrection(true)
                }
            }
            .textFieldStyle(.settings)
            .frame(width: compact ? 250 : 280)
        }
    }

    private func buttonRow<Buttons: View>(message: (String, Bool)?, @ViewBuilder buttons: () -> Buttons) -> some View {
        HStack(spacing: DS.Space.s8) {
            if let message {
                Text(message.0)
                    .font(.system(size: 11.5))
                    .foregroundStyle(message.1 ? theme.success : theme.warning)
                    .lineLimit(2)
            }
            Spacer(minLength: DS.Space.s8)
            buttons()
        }
        .padding(.horizontal, DS.Space.s12)
        .padding(.vertical, DS.Space.s8)
    }
}

/// Settings > Live TV.
struct LiveTVSettingsView: View {
    var body: some View {
        LiveTVSettingsForm()
    }
}

/// First entry without an account, and "Live TV settings…" inside the mode.
struct LiveTVSetupSheet: View {
    let onDone: () -> Void
    @ObservedObject private var store = LiveTVStore.shared
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: DS.Space.s4) {
                    HStack(spacing: DS.Space.s8) {
                        LiveDot()
                        Text(store.isConfigured ? "Live TV settings" : "Set up Live TV").flixorFont(.title2, weight: .bold)
                    }
                    Text("Your US and Indian lineup from xtream-web, played in Flixor.")
                        .flixorFont(.callout).foregroundStyle(theme.textSecondary)
                }
                Spacer()
                LiveTVIconButton(icon: "xmark", help: "Close", size: 30, action: onDone)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.bottom, DS.Space.s8)
            ScrollView(showsIndicators: false) {
                LiveTVSettingsForm(compact: true) {
                    onDone()
                    store.loadCatalog(force: false)
                }
                .padding(.vertical, DS.Space.s12)
            }
        }
        .padding(DS.Space.s24)
        .frame(width: 540, height: 680)
        .background(theme.surfaceElevated)
        .toggleStyle(.settingsSwitch)
        .tint(SettingsChrome.neutralTint)
    }
}
#endif
