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
        VStack(alignment: .leading, spacing: DS.Space.s14) {
            if !compact {
                section("Live TV mode", note: "Personal build only.") {
                    Toggle("Show Live TV in Flixor", isOn: $store.featureEnabled)
                    Toggle("Open Flixor in Live TV", isOn: $store.openOnLaunch)
                        .disabled(!store.featureEnabled)
                }
            }

            section("Xtream account", note: "Saved in your Keychain. Flixor talks to the provider directly.") {
                field("Name", text: $name, prompt: "My IPTV")
                field("Server URL", text: $serverURL, prompt: "http://provider.example:8080")
                HStack(spacing: 10) {
                    field("Username", text: $username, prompt: "")
                    secureField("Password", text: $password)
                }
                HStack(spacing: DS.Space.s8) {
                    LiveTVFormButton(title: testingAccount ? "Testing…" : "Test connection", enabled: !testingAccount && draftAccount != nil) {
                        Task { await testAccount() }
                    }
                    if store.account != nil {
                        LiveTVFormButton(title: "Remove", destructive: true) {
                            store.saveAccount(nil)
                            loadFields()
                            accountMessage = ("Account removed.", true)
                        }
                    }
                    if let accountMessage { status(accountMessage) }
                }
            }

            section("Guide server (xtream-web)", note: "The guide comes from your xtream-web server: its YouTube TV, India and premium schedules, with the provider guide as fallback.") {
                field("Address", text: $guideURL, prompt: "https://tv.example.app")
                secureField("Sign-in password", text: $guidePassword)
                HStack(spacing: DS.Space.s8) {
                    LiveTVFormButton(title: testingGuide ? "Signing in…" : "Test sign-in", enabled: !testingGuide && draftGuide != nil) {
                        Task { await testGuide() }
                    }
                    if store.guideServer != nil {
                        LiveTVFormButton(title: "Remove", destructive: true) {
                            store.saveGuideServer(nil)
                            loadFields()
                            guideMessage = ("Guide server removed. The provider guide is used.", true)
                        }
                    }
                    if let guideMessage { status(guideMessage) }
                }
            }

            section("Curated lineup", note: nil) {
                lineupStatus
            }

            HStack {
                Spacer()
                LiveTVFormButton(title: compact ? "Save and open Live TV" : "Save", prominent: true, enabled: draftAccount != nil) { save() }
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
        if let rules {
            Text("Exported from xtream-web \(rules.generatedAt.prefix(10)) · \(rules.referenceLineup.count) US reference channels, \(rules.indianFeeds.count) Indian channels, \(rules.verifiedSources.count) verified sources")
                .flixorFont(.callout).foregroundStyle(theme.textSecondary)
            if !store.lineup.isEmpty {
                Text("Matched on your provider: \(store.lineup.filter { $0.market == .us }.count) US and \(store.lineup.filter { $0.market == .india }.count) Indian channels")
                    .flixorFont(.callout).foregroundStyle(theme.textSecondary)
            }
        } else {
            Text("Not found. Run the xtream-web lineup export on this Mac; it writes ~/Library/Application Support/Flixor/LiveTV/curated-lineup.json.")
                .flixorFont(.callout).foregroundStyle(theme.warning)
        }
        HStack(spacing: DS.Space.s8) {
            LiveTVFormButton(title: "Show in Finder") {
                try? FileManager.default.createDirectory(at: LiveTVStore.supportDirectory, withIntermediateDirectories: true)
                NSWorkspace.shared.activateFileViewerSelecting([rules != nil ? url : LiveTVStore.supportDirectory])
            }
            if store.isConfigured {
                LiveTVFormButton(title: "Reload channels") { store.loadCatalog(force: true) }
            }
        }
    }

    // MARK: Pieces

    private func section<Content: View>(_ title: String, note: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s10) {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                Text(title).flixorFont(.headline, weight: .semibold).foregroundStyle(theme.textPrimary)
                if let note { Text(note).flixorFont(.callout).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true) }
            }
            content()
        }
        .padding(DS.Space.s16)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: DS.Radius.group, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.group, style: .continuous).strokeBorder(theme.separator, lineWidth: DS.Border.thin))
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        LiveTVTextField(label: label, text: text, placeholder: prompt, secure: false)
    }

    private func secureField(_ label: String, text: Binding<String>) -> some View {
        LiveTVTextField(label: label, text: text, placeholder: "", secure: true)
    }

    private func status(_ message: (String, Bool)) -> some View {
        Text(message.0).flixorFont(.footnote).foregroundStyle(message.1 ? theme.success : theme.warning).lineLimit(2)
    }
}

/// Text field in Flixor's style: dim placeholder, quiet outline, focus ring.
struct LiveTVTextField: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    let secure: Bool
    @FocusState private var focused: Bool
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            Text(label).flixorFont(.caption, weight: .medium).foregroundStyle(theme.textTertiary)
            ZStack(alignment: .leading) {
                if text.isEmpty && !placeholder.isEmpty {
                    Text(placeholder).flixorFont(.body).foregroundStyle(theme.textDisabled).allowsHitTesting(false)
                }
                Group {
                    if secure { SecureField("", text: $text) } else { TextField("", text: $text).disableAutocorrection(true) }
                }
                .textFieldStyle(.plain)
                .flixorFont(.body)
                .foregroundStyle(theme.textPrimary)
                .focused($focused)
            }
            .padding(.horizontal, DS.Space.s12)
            .frame(height: 36)
            .background(Color.white.opacity(DS.Opacity.subtle), in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                .strokeBorder(focused ? Color.white.opacity(0.45) : theme.separatorStrong, lineWidth: DS.Border.thin))
        }
    }
}

/// Buttons for the form: prominent (white), secondary (grey) or destructive (red text).
struct LiveTVFormButton: View {
    let title: String
    var prominent = false
    var destructive = false
    var enabled = true
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        Button(action: action) {
            Text(title)
                .flixorFont(.callout, weight: .semibold)
                .foregroundStyle(prominent ? Color.black : destructive ? theme.danger : theme.textPrimary)
                .padding(.horizontal, DS.Space.s14)
                .frame(height: 32)
                .background(Capsule().fill(prominent ? Color.white.opacity(hovering ? 0.9 : 1) : Color.white.opacity(hovering ? 0.14 : 0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : DS.Opacity.disabled)
        .onHover { hovering = $0 && enabled }
    }
}

/// Settings > Live TV.
struct LiveTVSettingsView: View {
    var body: some View {
        LiveTVSettingsForm()
            .padding(.vertical, 4)
            .frame(maxWidth: 620, alignment: .leading)
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
        .tint(.white)
    }
}
#endif
