//
//  AISettings.swift
//  FlixorMac
//
//  Per-profile AI settings. Everything AI is behind one master switch,
//  `isEnabled`, which is OFF by default: while it's off no AI request is made
//  (Apple Intelligence included) and no AI control is shown anywhere. Keys for
//  OpenAI and Anthropic live in the Keychain (SecretStore), never in
//  UserDefaults or logs.
//

import Combine
import Foundation

enum AIEngineKind: String, CaseIterable, Identifiable {
    case apple
    case openAI
    case anthropic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .apple: return String(localized: "Apple Intelligence")
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic"
        }
    }

    var shortLabel: String {
        switch self {
        case .apple: return "Apple"
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic"
        }
    }
}

@MainActor
final class AISettings: ObservableObject {
    static let shared = AISettings()

    private enum Keys {
        static let enabled = "aiEnabled"
        static let engine = "aiEngine"
        static let anthropicModel = "aiAnthropicModel"
        static let anthropicQuickModel = "aiAnthropicQuickModel"
        static let openAIModel = "aiOpenAIModel"
        static let openAIQuickModel = "aiOpenAIQuickModel"
        static let fallbackToApple = "aiFallbackToApple"
        static let describeSearch = "aiDescribeSearch"
        static let askFlixor = "aiAskFlixor"
        static let recaps = "aiRecaps"
        static let why = "aiWhy"
        static let moodPicks = "aiMoodPicks"
        static let xray = "aiXRay"
        // Keychain accounts (profile-scoped).
        static let anthropicKey = "aiAnthropicKey"
        static let openAIKey = "aiOpenAIKey"
    }

    static let defaultAnthropicModel = "claude-opus-5-5"
    static let defaultAnthropicQuickModel = "claude-haiku-5-5"

    private let defaults = UserDefaults.standard
    private var profileObserver: AnyCancellable?
    private var isReloading = false

    /// Master switch. Off by default.
    @Published var isEnabled: Bool { didSet { save(isEnabled, Keys.enabled) } }
    @Published var engine: AIEngineKind { didSet { save(engine.rawValue, Keys.engine) } }
    @Published var anthropicModel: String { didSet { save(anthropicModel, Keys.anthropicModel) } }
    @Published var anthropicQuickModel: String { didSet { save(anthropicQuickModel, Keys.anthropicQuickModel) } }
    @Published var openAIModel: String { didSet { save(openAIModel, Keys.openAIModel) } }
    @Published var openAIQuickModel: String { didSet { save(openAIQuickModel, Keys.openAIQuickModel) } }
    /// Use Apple Intelligence when a cloud request fails.
    @Published var fallbackToApple: Bool { didSet { save(fallbackToApple, Keys.fallbackToApple) } }
    /// Feature: Search by description.
    @Published var describeSearchEnabled: Bool { didSet { save(describeSearchEnabled, Keys.describeSearch) } }
    /// Feature: Ask Flixor chat panel.
    @Published var askFlixorEnabled: Bool { didSet { save(askFlixorEnabled, Keys.askFlixor) } }
    /// Feature: "Previously on" recaps on show Details.
    @Published var recapsEnabled: Bool { didSet { save(recapsEnabled, Keys.recaps) } }
    /// Feature: "Why you'd like it" line on Details.
    @Published var whyEnabled: Bool { didSet { save(whyEnabled, Keys.why) } }
    /// Feature: mood picks row on Home.
    @Published var moodPicksEnabled: Bool { didSet { save(moodPicksEnabled, Keys.moodPicks) } }
    /// Feature: X-Ray in the player (on-device face recognition).
    @Published var xrayEnabled: Bool { didSet { save(xrayEnabled, Keys.xray) } }
    /// Bumped when a key changes so views re-read `hasKey`.
    @Published private(set) var keyRevision = 0

    private init() {
        isEnabled = false
        engine = .apple
        anthropicModel = Self.defaultAnthropicModel
        anthropicQuickModel = Self.defaultAnthropicQuickModel
        openAIModel = ""
        openAIQuickModel = ""
        fallbackToApple = true
        describeSearchEnabled = true
        askFlixorEnabled = true
        recapsEnabled = true
        whyEnabled = true
        moodPicksEnabled = true
        xrayEnabled = true
        reload()
        profileObserver = ProfileSettings.shared.objectWillChange
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.reload() }
            }
    }

    /// Re-reads the current profile's values.
    func reload() {
        isReloading = true
        defer { isReloading = false }
        let enabled = bool(Keys.enabled, default: false)
        if enabled != isEnabled { isEnabled = enabled }
        let kind = AIEngineKind(rawValue: defaults.string(forKey: key(Keys.engine)) ?? "") ?? .apple
        if kind != engine { engine = kind }
        let am = string(Keys.anthropicModel, default: Self.defaultAnthropicModel)
        if am != anthropicModel { anthropicModel = am }
        let aq = string(Keys.anthropicQuickModel, default: Self.defaultAnthropicQuickModel)
        if aq != anthropicQuickModel { anthropicQuickModel = aq }
        let om = string(Keys.openAIModel, default: "")
        if om != openAIModel { openAIModel = om }
        let oq = string(Keys.openAIQuickModel, default: "")
        if oq != openAIQuickModel { openAIQuickModel = oq }
        let fb = bool(Keys.fallbackToApple, default: true)
        if fb != fallbackToApple { fallbackToApple = fb }
        let ds = bool(Keys.describeSearch, default: true)
        if ds != describeSearchEnabled { describeSearchEnabled = ds }
        let ask = bool(Keys.askFlixor, default: true)
        if ask != askFlixorEnabled { askFlixorEnabled = ask }
        let rc = bool(Keys.recaps, default: true)
        if rc != recapsEnabled { recapsEnabled = rc }
        let wy = bool(Keys.why, default: true)
        if wy != whyEnabled { whyEnabled = wy }
        let mp = bool(Keys.moodPicks, default: true)
        if mp != moodPicksEnabled { moodPicksEnabled = mp }
        let xr = bool(Keys.xray, default: true)
        if xr != xrayEnabled { xrayEnabled = xr }
        keyRevision += 1
    }

    // MARK: Features

    /// Search by description is on (master switch and its own switch).
    var isDescribeSearchActive: Bool { isEnabled && describeSearchEnabled }
    var isAskFlixorActive: Bool { isEnabled && askFlixorEnabled }
    var isRecapActive: Bool { isEnabled && recapsEnabled }
    var isWhyActive: Bool { isEnabled && whyEnabled }
    var isMoodPicksActive: Bool { isEnabled && moodPicksEnabled }
    var isXRayActive: Bool { isEnabled && xrayEnabled }

    // MARK: Keys

    func apiKey(for kind: AIEngineKind) -> String {
        switch kind {
        case .apple: return ""
        case .openAI: return defaults.secret(forKey: key(Keys.openAIKey))
        case .anthropic: return defaults.secret(forKey: key(Keys.anthropicKey))
        }
    }

    func setAPIKey(_ value: String, for kind: AIEngineKind) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .apple: return
        case .openAI: defaults.setSecret(trimmed, forKey: key(Keys.openAIKey))
        case .anthropic: defaults.setSecret(trimmed, forKey: key(Keys.anthropicKey))
        }
        keyRevision += 1
    }

    func hasKey(for kind: AIEngineKind) -> Bool { !apiKey(for: kind).isEmpty }

    /// The current key passed its last test. Stored as a short fingerprint of
    /// the key (not the key), so a new key starts unverified.
    func isKeyVerified(for kind: AIEngineKind) -> Bool {
        _ = keyRevision
        let key = apiKey(for: kind)
        guard !key.isEmpty else { return false }
        return defaults.string(forKey: self.key("aiKeyVerified_\(kind.rawValue)")) == Self.fingerprint(key)
    }

    func setKeyVerified(_ verified: Bool, for kind: AIEngineKind) {
        let storageKey = key("aiKeyVerified_\(kind.rawValue)")
        if verified { defaults.set(Self.fingerprint(apiKey(for: kind)), forKey: storageKey) } else { defaults.removeObject(forKey: storageKey) }
        keyRevision += 1
    }

    private static func fingerprint(_ key: String) -> String {
        var hash: UInt64 = 5381
        for byte in key.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return String(hash, radix: 36)
    }

    /// Model for a request on a cloud engine.
    func model(for kind: AIEngineKind, quick: Bool) -> String {
        switch kind {
        case .apple: return "apple"
        case .anthropic:
            let chosen = quick ? anthropicQuickModel : anthropicModel
            return chosen.isEmpty ? (quick ? Self.defaultAnthropicQuickModel : Self.defaultAnthropicModel) : chosen
        case .openAI:
            let chosen = quick ? openAIQuickModel : openAIModel
            return chosen.isEmpty ? openAIModel : chosen
        }
    }

    // MARK: Storage

    private func key(_ base: String) -> String { defaults.profileKey(base) }

    private func save(_ value: Any, _ base: String) {
        guard !isReloading else { return }
        defaults.set(value, forKey: key(base))
    }

    private func bool(_ base: String, default value: Bool) -> Bool {
        defaults.object(forKey: key(base)) as? Bool ?? value
    }

    private func string(_ base: String, default value: String) -> String {
        defaults.string(forKey: key(base)) ?? value
    }
}
