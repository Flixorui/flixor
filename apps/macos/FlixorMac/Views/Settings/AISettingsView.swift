//
//  AISettingsView.swift
//  FlixorMac
//
//  Settings → AI: the master switch (off by default), the engine (Apple
//  Intelligence, or the user's own OpenAI or Anthropic key), models, and the
//  per-feature switches. Keys go to the Keychain; the page only shows a masked
//  form ("sk-ant-…••••••• 7Q2f") with whether the key last worked.
//

import SwiftUI

struct AISettingsView: View {
    @Environment(\.flixorTheme) private var theme
    @ObservedObject private var settings = AISettings.shared

    @State private var isEditingKey = false
    @State private var keyDraft = ""
    @State private var models: [AIModelInfo] = []
    @State private var isLoadingModels = false
    @State private var modelsError: String?
    @State private var testState: TestState = .idle
    @State private var showsSentDetails = false
    @State private var xrayUsage: (titles: Int, bytes: Int64)?
    @State private var confirmsXRayClear = false

    private enum TestState: Equatable {
        case idle, running, passed(String), failed(String)
    }

    private static let tint = Color(hex: 0xA78BFA)

    private var engine: AIEngineKind { settings.engine }
    private var savedKey: String { _ = settings.keyRevision; return settings.apiKey(for: engine) }
    private var hasKey: Bool { !savedKey.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            SettingsGroupCard {
                masterRow
                Group {
                    divider
                    engineRow
                    if engine == .apple {
                        divider
                        appleRow
                    } else {
                        divider
                        keyRow
                        divider
                        SettingsRow(title: "Model", subtitle: "Listed from your account") { modelPicker(quick: false) }
                        SettingsRow(title: "Quick tasks model", subtitle: "Search parsing, one-liners (cheaper and faster)") { modelPicker(quick: true) }
                        SettingsRow(title: "Fall back to Apple Intelligence", subtitle: "If the key fails or you're offline", showDivider: false) {
                            Toggle("", isOn: $settings.fallbackToApple).labelsHidden()
                        }
                    }
                }
                .disabled(!settings.isEnabled)
                .opacity(settings.isEnabled ? 1 : 0.45)
            }

            SettingsGroupCard {
                featureRow("Search by description", isOn: $settings.describeSearchEnabled)
                featureRow("Ask Flixor", subtitle: "⌘J on any screen", isOn: $settings.askFlixorEnabled)
                featureRow("\"Previously on\" recaps", isOn: $settings.recapsEnabled)
                featureRow("\"Why you'd like it\"", isOn: $settings.whyEnabled)
                featureRow("Mood picks row", isOn: $settings.moodPicksEnabled)
                featureRow("X-Ray in the player", subtitle: "Who's in each scene, matched on this Mac · X while playing", isOn: $settings.xrayEnabled)
                xrayDataRow
                sentRow
            }
            .disabled(!settings.isEnabled)
            .opacity(settings.isEnabled ? 1 : 0.45)

            if settings.isEnabled, engine != .apple, let modelsError {
                Label(modelsError, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.warning)
                    .padding(.horizontal, DS.Space.s4)
            }
        }
        .onChange(of: settings.engine) { _ in
            models = []
            modelsError = nil
            testState = .idle
            isEditingKey = false
            keyDraft = ""
            loadModelsIfPossible()
        }
        .onChange(of: settings.isEnabled) { _ in loadModelsIfPossible() }
        .task { loadModelsIfPossible() }
    }

    // MARK: Rows

    private var masterRow: some View {
        HStack(alignment: .center, spacing: DS.Space.s12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("AI Features").font(.system(size: 13, weight: .semibold))
                Text("Off by default. When off, Flixor makes no AI requests and hides every AI button, row and line.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DS.Space.s12)
            Toggle("", isOn: $settings.isEnabled)
                .labelsHidden()
                .accessibilityLabel(Text("AI features"))
        }
        .padding(.horizontal, DS.Space.s12)
        .padding(.vertical, DS.Space.s12)
        .background(Self.tint.opacity(0.08))
    }

    private var engineRow: some View {
        SettingsRow(title: "Engine", subtitle: "Which model answers", showDivider: false) {
            Picker("", selection: $settings.engine) {
                ForEach(AIEngineKind.allCases) { Text($0.shortLabel).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }

    private var appleRow: some View {
        HStack(spacing: DS.Space.s10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Apple Intelligence").font(.system(size: 13))
                Text(AppleEngine.availability ?? String(localized: "On this Mac. Free, private and works offline."))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusLabel
            testButton
        }
        .padding(.horizontal, DS.Space.s12)
        .padding(.vertical, DS.Space.s10)
    }

    @ViewBuilder
    private var keyRow: some View {
        if isEditingKey || !hasKey {
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                HStack {
                    Text("\(engine.label) API key").font(.system(size: 13))
                    Spacer()
                    Link("Get a key ↗",
                         destination: URL(string: engine == .anthropic ? "https://console.anthropic.com/settings/keys" : "https://platform.openai.com/api-keys")!)
                        .font(.system(size: 11.5))
                }
                HStack(spacing: DS.Space.s8) {
                    SecureField("Paste your \(engine.label) API key", text: $keyDraft)
                        .textFieldStyle(.settings)
                        .onSubmit(saveKey)
                    Button("Save", action: saveKey)
                        .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    if hasKey {
                        Button("Cancel") { isEditingKey = false; keyDraft = "" }
                    }
                }
                Text("Stored in your Keychain").font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, DS.Space.s12)
            .padding(.vertical, DS.Space.s10)
        } else {
            HStack(spacing: DS.Space.s10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(engine.label) API key").font(.system(size: 13))
                    Text("Stored in your Keychain").font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                Spacer()
                Text(Self.masked(savedKey))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, DS.Space.s10)
                    .padding(.vertical, DS.Space.s4)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.r6).fill(Color.white.opacity(0.07)))
                statusLabel
                Menu {
                    Button("Test") { runTest() }
                    Button("Change Key…") { isEditingKey = true }
                    Divider()
                    Button("Remove Key", role: .destructive) {
                        settings.setAPIKey("", for: engine)
                        models = []
                        testState = .idle
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel(Text("Key options"))
            }
            .padding(.horizontal, DS.Space.s12)
            .padding(.vertical, DS.Space.s10)
        }
    }

    private func featureRow(_ title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, isOn: Binding<Bool>) -> some View {
        SettingsRow(title: title, subtitle: subtitle) {
            Toggle("", isOn: isOn).labelsHidden()
        }
    }

    private var xrayDataRow: some View {
        SettingsRow(title: "Saved X-Ray data", subtitle: xrayUsageText) {
            Button("Clear…") { confirmsXRayClear = true }
                .disabled((xrayUsage?.bytes ?? 0) == 0)
                .confirmationDialog("Clear saved X-Ray data?", isPresented: $confirmsXRayClear) {
                    Button("Clear", role: .destructive) {
                        Task {
                            await XRayStore.shared.clearAll()
                            xrayUsage = await XRayStore.shared.usage()
                        }
                    }
                } message: {
                    Text("Titles you watch again will be analysed again.")
                }
        }
        .task { xrayUsage = await XRayStore.shared.usage() }
    }

    private var xrayUsageText: LocalizedStringKey {
        guard let usage = xrayUsage else { return "Scenes and cast faces, kept on this Mac" }
        let size = ByteCountFormatter.string(fromByteCount: usage.bytes, countStyle: .file)
        return usage.titles == 1 ? "1 title · \(size)" : "\(usage.titles) titles · \(size)"
    }

    private var sentRow: some View {
        SettingsRow(
            title: "What's sent",
            subtitle: engine == .apple
                ? "Nothing leaves this Mac with Apple Intelligence."
                : "Titles, years, genres and your ratings for the request at hand. Never account names, server addresses, tokens or file paths.",
            showDivider: false
        ) {
            Button("Details ›") { showsSentDetails = true }
                .buttonStyle(.borderless)
                .popover(isPresented: $showsSentDetails, arrowEdge: .trailing) {
                    Text(sentExplanation)
                        .font(.system(size: 12))
                        .frame(width: 320)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(DS.Space.s14)
                }
        }
    }

    // MARK: Status and test

    @ViewBuilder
    private var statusLabel: some View {
        switch testState {
        case .running:
            ProgressView().controlSize(.small)
        case .passed(let detail):
            Label("Works", systemImage: "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.success)
                .help(detail)
        case .failed(let message):
            Label("Didn't work", systemImage: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.danger)
                .help(message)
        case .idle:
            if engine != .apple, hasKey, settings.isKeyVerified(for: engine) {
                Label("Works", systemImage: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.success)
            }
        }
    }

    private var testButton: some View {
        Button("Test") { runTest() }
            .disabled(testState == .running || AppleEngine.availability != nil)
    }

    private func runTest() {
        testState = .running
        let kind = engine
        let key = settings.apiKey(for: kind)
        let model = settings.model(for: kind, quick: true)
        Task { @MainActor in
            let request = AIStructuredRequest(
                instructions: "Answer with the JSON requested.",
                prompt: "Name one well-known 1990s heist film.",
                schema: .object(name: "Answer", properties: [
                    AISchemaProperty(name: "title", description: "Film title", schema: .string()),
                    AISchemaProperty(name: "year", description: "Release year", schema: .integer)
                ])
            )
            let started = Date()
            do {
                let data = try await AIService.generate(request, kind: kind, key: key, model: model)
                struct Answer: Decodable { let title: String; let year: Int }
                let answer = try JSONDecoder().decode(Answer.self, from: data)
                let seconds = String(format: "%.1f", Date().timeIntervalSince(started))
                let name = kind == .apple ? kind.label : model
                testState = .passed(String(localized: "\(name) answered “\(answer.title) (\(String(answer.year)))” in \(seconds)s"))
                settings.setKeyVerified(true, for: kind)
            } catch {
                testState = .failed(error.localizedDescription)
                settings.setKeyVerified(false, for: kind)
            }
        }
    }

    // MARK: Models

    private func modelPicker(quick: Bool) -> some View {
        let binding: Binding<String> = {
            switch (engine, quick) {
            case (.anthropic, false): return $settings.anthropicModel
            case (.anthropic, true): return $settings.anthropicQuickModel
            case (_, false): return $settings.openAIModel
            case (_, true): return $settings.openAIQuickModel
            }
        }()
        var options = models
        let current = binding.wrappedValue
        if !current.isEmpty, !options.contains(where: { $0.id == current }) {
            options.insert(AIModelInfo(id: current, name: current), at: 0)
        }
        return Group {
            if isLoadingModels && options.isEmpty {
                ProgressView().controlSize(.small)
            } else {
                Picker("", selection: binding) {
                    if current.isEmpty { Text("Choose…").tag("") }
                    ForEach(options) { Text($0.name).tag($0.id) }
                }
                .labelsHidden()
                .fixedSize()
                .disabled(options.isEmpty)
            }
        }
    }

    private func saveKey() {
        let value = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        settings.setAPIKey(value, for: engine)
        keyDraft = ""
        isEditingKey = false
        loadModelsIfPossible()
        runTest()
    }

    private func loadModelsIfPossible() {
        guard engine != .apple, settings.isEnabled, hasKey, !isLoadingModels else { return }
        isLoadingModels = true
        modelsError = nil
        let kind = engine
        let key = settings.apiKey(for: kind)
        Task { @MainActor in
            defer { isLoadingModels = false }
            do {
                let list = try await AIService.listModels(kind: kind, key: key)
                guard kind == settings.engine else { return }
                models = list
                if kind == .openAI, settings.openAIModel.isEmpty, let first = list.first {
                    settings.openAIModel = first.id
                    if settings.openAIQuickModel.isEmpty {
                        settings.openAIQuickModel = list.first { $0.id.contains("mini") }?.id ?? first.id
                    }
                }
            } catch {
                modelsError = error.localizedDescription
            }
        }
    }

    // MARK: Helpers

    /// "sk-ant-…••••••• 7Q2f": enough to recognise the key, not to use it.
    static func masked(_ key: String) -> String {
        guard key.count > 12 else { return "••••••••" }
        let head = key.prefix(10)
        let prefix = head.lastIndex(of: "-").map { String(head[...$0]) } ?? String(key.prefix(3))
        return "\(prefix)…••••••• \(key.suffix(4))"
    }

    private var sentExplanation: String {
        switch engine {
        case .apple:
            return String(localized: "With Apple Intelligence everything runs on this Mac and nothing is sent anywhere. X-Ray also runs on this Mac with any engine: faces are matched against the cast's TMDB photos and nothing is uploaded.")
        case .openAI, .anthropic:
            return String(localized: "With \(engine.label), each request sends only what that feature needs: what you typed, and for some features titles, years, genres, episode summaries from TMDB and your ratings. Never account names, server addresses, tokens or file paths. Requests are billed to your \(engine.label) account. X-Ray never uses your key: it matches faces on this Mac.")
        }
    }

    private var divider: some View {
        Divider().padding(.leading, DS.Space.s12)
    }
}
