//
//  StreamingAvailabilityBudget.swift
//  FlixorMac
//
//  Hard limits on API calls, per API key: a daily cap counted on this Mac and a
//  monthly floor using the quota the API reports for that key. With several
//  keys, each request goes to the key with the most calls left, so more keys
//  means more calls.
//

import Foundation
import CryptoKit

@MainActor
final class StreamingAvailabilityBudget: ObservableObject {
    static let shared = StreamingAvailabilityBudget()

    /// A key stops being used once its month has this few calls left.
    static let monthlyReserve = 10

    private enum Keys {
        static let day = "streamingAvailability.budget.day"
        static let month = "streamingAvailability.budget.month"
        static let dayCounts = "streamingAvailability.budget.dayCounts"
        static let monthCounts = "streamingAvailability.budget.monthCounts"
        static let quotas = "streamingAvailability.budget.quotas"
        static let dailyLimit = "streamingAvailability.dailyLimit"
        // Single-key counters from the first version (kept for the migration).
        static let legacyDayCount = "streamingAvailability.budget.dayCount"
        static let legacyMonthCount = "streamingAvailability.budget.monthCount"
        static let legacyQuota = "streamingAvailability.budget.quota"
    }

    private let defaults = UserDefaults.standard

    /// Calls today / this month, by key fingerprint.
    @Published private(set) var dayCounts: [String: Int] = [:]
    @Published private(set) var monthCounts: [String: Int] = [:]
    /// Last quota the API reported, by key fingerprint.
    @Published private(set) var quotas: [String: SAQuota] = [:]
    /// Daily cap for each key.
    @Published var dailyLimit: Int {
        didSet { defaults.set(dailyLimit, forKey: Keys.dailyLimit) }
    }

    private init() {
        let stored = defaults.integer(forKey: Keys.dailyLimit)
        dailyLimit = stored == 0 ? 25 : min(max(stored, 5), 40)
        dayCounts = (defaults.dictionary(forKey: Keys.dayCounts) as? [String: Int]) ?? [:]
        monthCounts = (defaults.dictionary(forKey: Keys.monthCounts) as? [String: Int]) ?? [:]
        if let data = defaults.data(forKey: Keys.quotas) {
            quotas = (try? JSONDecoder().decode([String: SAQuota].self, from: data)) ?? [:]
        }
        rollOver()
    }

    static func fingerprint(_ key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    /// Moves the first version's single-key counters onto `fingerprint`.
    func adoptLegacyCounters(for fingerprint: String) {
        guard defaults.object(forKey: Keys.legacyDayCount) != nil || defaults.object(forKey: Keys.legacyQuota) != nil else { return }
        if dayCounts[fingerprint] == nil { dayCounts[fingerprint] = defaults.integer(forKey: Keys.legacyDayCount) }
        if monthCounts[fingerprint] == nil { monthCounts[fingerprint] = defaults.integer(forKey: Keys.legacyMonthCount) }
        if quotas[fingerprint] == nil, let data = defaults.data(forKey: Keys.legacyQuota),
           let quota = try? JSONDecoder().decode(SAQuota.self, from: data) { quotas[fingerprint] = quota }
        [Keys.legacyDayCount, Keys.legacyMonthCount, Keys.legacyQuota].forEach(defaults.removeObject(forKey:))
        persist()
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .autoupdatingCurrent
        return f
    }()

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"; f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private static func dayString(_ date: Date = Date()) -> String {
        dayFormatter.string(from: date)
    }

    private static func monthString(_ date: Date = Date()) -> String {
        monthFormatter.string(from: date)
    }

    /// Clears the counters when the day or month changed. Only called before
    /// spending, never while a view reads, so it can't cause a redraw loop.
    private func rollOver() {
        if defaults.string(forKey: Keys.day) != Self.dayString() {
            defaults.set(Self.dayString(), forKey: Keys.day)
            if !dayCounts.isEmpty { dayCounts = [:] }
        }
        if defaults.string(forKey: Keys.month) != Self.monthString() {
            defaults.set(Self.monthString(), forKey: Keys.month)
            if !monthCounts.isEmpty { monthCounts = [:] }
        }
        persist()
    }

    private func persist() {
        defaults.set(dayCounts, forKey: Keys.dayCounts)
        defaults.set(monthCounts, forKey: Keys.monthCounts)
        if let data = try? JSONEncoder().encode(quotas) { defaults.set(data, forKey: Keys.quotas) }
    }

    private var isNewDay: Bool { defaults.string(forKey: Keys.day) != Self.dayString() }

    func callsToday(_ fingerprint: String) -> Int { isNewDay ? 0 : (dayCounts[fingerprint] ?? 0) }

    /// Calls left today for one key, after both limits. Read-only.
    func allowance(_ fingerprint: String) -> Int {
        let daily = max(0, dailyLimit - callsToday(fingerprint))
        guard let quota = quotas[fingerprint], quota.resetsAt.map({ $0 > Date() }) ?? true else { return daily }
        return min(daily, max(0, quota.remaining - Self.monthlyReserve))
    }

    /// Calls left today across `fingerprints`.
    func totalAllowance(_ fingerprints: [String]) -> Int {
        fingerprints.reduce(0) { $0 + allowance($1) }
    }

    func totalCallsToday(_ fingerprints: [String]) -> Int {
        fingerprints.reduce(0) { $0 + callsToday($1) }
    }

    /// Reserves one call on the key with the most calls left; nil means no request may be made.
    func spend(among fingerprints: [String]) -> String? {
        rollOver()
        guard let best = fingerprints.max(by: { allowance($0) < allowance($1) }), allowance(best) > 0 else { return nil }
        dayCounts[best, default: 0] += 1
        monthCounts[best, default: 0] += 1
        persist()
        return best
    }

    func record(_ quota: SAQuota?, for fingerprint: String) {
        guard let quota else { return }
        quotas[fingerprint] = quota
        persist()
    }

    /// The API said this key's quota is used up (HTTP 429): stop using it until the reset.
    func markExhausted(_ fingerprint: String) {
        let old = quotas[fingerprint]
        quotas[fingerprint] = SAQuota(used: old?.granted ?? 1000, granted: old?.granted ?? 1000,
                                      resetsAt: old?.resetsAt ?? Self.nextMonthStart, observedAt: Date())
        persist()
    }

    func forget(_ fingerprint: String) {
        dayCounts[fingerprint] = nil
        monthCounts[fingerprint] = nil
        quotas[fingerprint] = nil
        persist()
    }

    private static var nextMonthStart: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))!
        return calendar.date(byAdding: .month, value: 1, to: start)!
    }
}
