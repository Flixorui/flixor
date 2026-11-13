//
//  MyBluraySettingsStore.swift
//  FlixorMac
//
//  Observable owner of the per-profile MyBluray settings
//  (UserDefaults+MyBluray.swift): the key, the master switch, the disc market
//  and every "what to show" choice. Settings and the screens that show
//  MyBluray data observe it.
//

import Combine
import SwiftUI

@MainActor
final class MyBluraySettingsStore: ObservableObject {
    static let shared = MyBluraySettingsStore()

    /// Where the saved key stands, from the last check this session.
    enum KeyStatus: Equatable {
        case none
        case unchecked
        case checking
        case valid(MyBlurayAccess)
        case invalid(String)
        /// The key couldn't be checked (offline, server down, rate limited).
        case unreachable(String)
    }

    private let defaults = UserDefaults.standard
    private var profileObserver: AnyCancellable?
    private var isLoading = false

    /// The saved key, or "" when none. Change it with `saveKey` / `removeKey`.
    @Published private(set) var apiKey: String
    @Published private(set) var keyStatus: KeyStatus = .none

    @Published var enabled: Bool {
        didSet {
            guard !isLoading, enabled != oldValue else { return }
            defaults.myblurayEnabled = enabled
        }
    }

    @Published var discCountry: String {
        didSet {
            guard !isLoading, discCountry != oldValue else { return }
            defaults.myblurayDiscCountry = discCountry
        }
    }

    @Published private var options: [MyBlurayOption: Bool]

    private init() {
        apiKey = defaults.myblurayApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        enabled = defaults.myblurayEnabled
        discCountry = defaults.myblurayDiscCountry
        options = Self.loadOptions(defaults)
        keyStatus = apiKey.isEmpty ? .none : .unchecked

        // Profile switches call ProfileSettings.reloadFromStorage(), which
        // republishes every setting; follow it (same approach as DetailsSectionsStore).
        profileObserver = ProfileSettings.shared.objectWillChange
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.reload()
                }
            }
    }

    // MARK: - Queries

    var hasKey: Bool { !apiKey.isEmpty }

    /// A key is saved and the master switch is on. Screens check this first.
    var isActive: Bool { hasKey && enabled }

    /// Whether a screen should show this: MyBluray is on, and so are the
    /// option and everything it depends on.
    func isOn(_ option: MyBlurayOption) -> Bool {
        isActive && isChosen(option) && !isBlocked(option)
    }

    /// The stored choice for this option alone.
    func isChosen(_ option: MyBlurayOption) -> Bool {
        options[option] ?? option.defaultValue
    }

    /// True when an option this one depends on is off.
    func isBlocked(_ option: MyBlurayOption) -> Bool {
        var parent = option.requires
        while let current = parent {
            if !isChosen(current) { return true }
            parent = current.requires
        }
        return false
    }

    /// The stored choice, whatever the master switch says. For Settings.
    func binding(_ option: MyBlurayOption) -> Binding<Bool> {
        Binding(
            get: { self.isChosen(option) },
            set: { value in
                self.options[option] = value
                self.defaults.setMyblurayOption(option, value)
            }
        )
    }

    /// The market to ask for disc releases: a country code, or nil for every country.
    var effectiveDiscCountry: String? {
        switch discCountry {
        case "all": return nil
        case "auto": return Self.localRegion
        default: return discCountry
        }
    }

    /// This Mac's region, when it's one Blu-ray.com lists; otherwise the US.
    static var localRegion: String {
        let code = Locale.current.region?.identifier.uppercased() ?? "US"
        return discCountries.contains(where: { $0.code == code }) ? code : "US"
    }

    /// Markets Blu-ray.com covers well, for the country picker.
    static let discCountries: [(code: String, name: String)] = [
        ("US", "United States"), ("GB", "United Kingdom"), ("CA", "Canada"),
        ("AU", "Australia"), ("DE", "Germany"), ("FR", "France"), ("IT", "Italy"),
        ("ES", "Spain"), ("NL", "Netherlands"), ("SE", "Sweden"), ("NO", "Norway"),
        ("DK", "Denmark"), ("FI", "Finland"), ("PL", "Poland"), ("JP", "Japan"),
        ("KR", "South Korea"), ("HK", "Hong Kong"), ("TW", "Taiwan"), ("CN", "China"),
        ("IN", "India"), ("BR", "Brazil"), ("MX", "Mexico"), ("NZ", "New Zealand"),
    ]

    /// `mbr_abc123…` for display; never the secret.
    var maskedKey: String {
        let parts = apiKey.split(separator: "_", maxSplits: 2)
        if parts.count == 3, parts[0] == "mbr" { return "mbr_\(parts[1])_••••••••" }
        return apiKey.isEmpty ? "" : String(apiKey.prefix(4)) + "••••••••"
    }

    // MARK: - Key

    /// Checks `draft` and saves it when the server accepts it. Returns an error
    /// message, or nil when saved. A key that can't be checked right now
    /// (offline, server down) isn't saved.
    func saveKey(_ draft: String) async -> String? {
        let key = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return String(localized: "Paste a key first.") }
        guard key.hasPrefix("mbr_") else { return String(localized: "MyBluray keys start with mbr_.") }

        let previous = keyStatus
        keyStatus = .checking
        do {
            let access = try await MyBlurayService.shared.checkKey(key)
            let changed = key != apiKey
            defaults.myblurayApiKey = key
            apiKey = key
            keyStatus = .valid(access)
            if changed { await MyBlurayService.shared.clearCache() }
            return nil
        } catch {
            keyStatus = previous
            return Self.message(for: error)
        }
    }

    /// Checks the saved key again, e.g. after changing its scopes in the portal.
    func checkKey() async {
        guard hasKey, keyStatus != .checking else { return }
        keyStatus = .checking
        do {
            let access = try await MyBlurayService.shared.checkKey(apiKey)
            keyStatus = .valid(access)
            if access.state(MyBlurayAccess.collection) == .yes { await MyBlurayService.shared.resetCollectionStatus() }
        } catch let error as MyBlurayError {
            if case .invalidKey = error {
                keyStatus = .invalid(Self.message(for: error))
            } else {
                keyStatus = .unreachable(Self.message(for: error))
            }
        } catch {
            keyStatus = .unreachable(Self.message(for: error))
        }
    }

    /// Checks the saved key once per session, when Settings first shows it.
    func checkKeyIfNeeded() async {
        if keyStatus == .unchecked { await checkKey() }
    }

    func removeKey() async {
        defaults.myblurayApiKey = ""
        apiKey = ""
        keyStatus = .none
        await MyBlurayService.shared.clearCache()
    }

    func resetDisplaySettings() {
        defaults.resetMyblurayDisplaySettings()
        reload()
    }

    static func message(for error: Error) -> String {
        switch error as? MyBlurayError {
        case .invalidKey(let code)?:
            switch code {
            case "API_KEY_REVOKED": return String(localized: "This key was revoked in the portal.")
            case "API_KEY_EXPIRED": return String(localized: "This key has expired.")
            default: return String(localized: "MyBluray didn't accept this key.")
            }
        case .rateLimited(_, let quotaExceeded)?:
            return quotaExceeded
                ? String(localized: "This key has used all its requests.")
                : String(localized: "Too many requests. Try again in a minute.")
        case .server?, .invalidResponse?:
            return String(localized: "MyBluray isn't responding. Try again later.")
        case .some(let error):
            return error.localizedDescription
        case nil:
            if error is URLError { return String(localized: "Couldn't reach MyBluray. Check your connection.") }
            return error.localizedDescription
        }
    }

    // MARK: - Loading

    private static func loadOptions(_ defaults: UserDefaults) -> [MyBlurayOption: Bool] {
        Dictionary(uniqueKeysWithValues: MyBlurayOption.allCases.map { ($0, defaults.myblurayOption($0)) })
    }

    private func reload() {
        isLoading = true
        defer { isLoading = false }
        let key = defaults.myblurayApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if key != apiKey {
            apiKey = key
            keyStatus = key.isEmpty ? .none : .unchecked
        }
        if enabled != defaults.myblurayEnabled { enabled = defaults.myblurayEnabled }
        if discCountry != defaults.myblurayDiscCountry { discCountry = defaults.myblurayDiscCountry }
        let loaded = Self.loadOptions(defaults)
        if loaded != options { options = loaded }
    }
}
