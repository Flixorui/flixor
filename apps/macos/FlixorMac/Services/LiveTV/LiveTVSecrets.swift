//
//  LiveTVSecrets.swift
//  FlixorMac
//
//  Personal build only (FLIXOR_LIVE_TV). Keychain storage for the Xtream
//  account, the xtream-web guide server and its session cookie. Everything is
//  kept in the Keychain (via SecretStore); the provider URL is private too.
//

#if FLIXOR_LIVE_TV
import Foundation

enum LiveTVSecrets {
    private static let accountKey = "liveTV.account"
    private static let guideServerKey = "liveTV.guideServer"
    private static let guideSessionKey = "liveTV.guideSession"

    static var account: LiveTVAccount? {
        get { decode(SecretStore.string(accountKey)) }
        set { SecretStore.set(encode(newValue), for: accountKey) }
    }

    static var guideServer: LiveTVGuideServer? {
        get { decode(SecretStore.string(guideServerKey)) }
        set {
            if newValue != guideServer { guideSessionCookie = nil }
            SecretStore.set(encode(newValue), for: guideServerKey)
        }
    }

    static var guideSessionCookie: String? {
        get { SecretStore.string(guideSessionKey) }
        set { SecretStore.set(newValue ?? "", for: guideSessionKey) }
    }

    private static func decode<T: Decodable>(_ text: String?) -> T? {
        guard let data = text?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func encode<T: Encodable>(_ value: T?) -> String {
        guard let value, let data = try? JSONEncoder().encode(value) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
#endif
