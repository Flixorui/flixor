//
//  StreamingAvailabilitySettingsView.swift
//  FlixorMac
//
//  Settings > Integrations > Streaming Availability (Movie of the Night):
//  your API key, which Top 10 and "New on" rows appear on Home, the region,
//  and the call budget that keeps usage inside the monthly quota.
//

import SwiftUI
import AppKit

struct StreamingAvailabilitySettingsView: View {
    @ObservedObject private var store = StreamingAvailabilityStore.shared
    @ObservedObject private var budget = StreamingAvailabilityBudget.shared

    @State private var keyDraft = ""
    @State private var isAdding = false
    @State private var addMessage: (String, Bool)?
    @State private var isRefreshing = false
    @State private var refetching: Set<String> = []
    @State private var changeToken = 0

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            SettingsGroupCard {
                SettingsStatusRow(status.0, title: status.1, subtitle: status.2)
                ForEach(store.keys) { key in
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.horizontal, DS.Space.s12)
                    keyRow(key)
                }
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.horizontal, DS.Space.s12)
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    Text(store.keys.isEmpty ? "API Key" : "Add Another Key").font(.system(size: 13))
                    HStack(spacing: DS.Space.s8) {
                        SecureField(String(localized: "Paste a Movie of the Night API key"), text: $keyDraft)
                            .textFieldStyle(.settings)
                            .onSubmit(addKey)
                        Button(isAdding ? String(localized: "Checking…") : String(localized: "Add"), action: addKey)
                            .buttonStyle(.settingsSecondary)
                            .disabled(isAdding || keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    HStack(spacing: DS.Space.s4) {
                        if let addMessage {
                            Text(addMessage.0).foregroundStyle(addMessage.1 ? Color.green : SettingsChrome.destructive)
                        } else {
                            Text(store.keys.isEmpty ? "Free key at" : "Each key adds its own 1,000 calls a month. Keys from").foregroundStyle(.secondary)
                            Link("developers.movieofthenight.com ↗", destination: URL(string: "https://developers.movieofthenight.com/")!)
                        }
                    }
                    .font(.system(size: 11.5))
                }
                .padding(.horizontal, DS.Space.s12)
                .padding(.vertical, DS.Space.s10)
            }

            if store.hasKey {
                SettingsSectionHeader(title: "Top 10 Rows")
                SettingsGroupCard {
                    SettingsRow(icon: "list.number", iconColor: Color(hex: "E50914"), title: "Show on Home",
                                subtitle: "Rows you can reorder or hide in Settings → Home") {
                        Toggle("", isOn: $store.enabled).labelsHidden()
                    }
                    SettingsRow(title: "Region", subtitle: "Charts and availability for this country") {
                        Picker("", selection: $store.region) {
                            ForEach(StreamingAvailabilityStore.regions, id: \.code) { region in
                                Text(region.name).tag(region.code)
                            }
                            if !StreamingAvailabilityStore.regions.contains(where: { $0.code == store.region }) {
                                Text(store.region.uppercased()).tag(store.region)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                    }
                    SettingsRow(title: "Movies and Shows", subtitle: store.splitByType ? "Two rows per service (2 calls per refresh)" : "One mixed row per service (1 call per refresh)") {
                        Picker("", selection: $store.splitByType) {
                            Text("Separate").tag(true)
                            Text("Mixed").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    ForEach(Array(store.availableServices.enumerated()), id: \.element) { index, service in
                        SettingsRow(title: LocalizedStringKey(service.displayName),
                                    showDivider: index < store.availableServices.count - 1) {
                            Toggle("", isOn: serviceBinding(service, in: \.topServices)).labelsHidden()
                        }
                    }
                }
                .disabled(!store.enabled)
                if store.regionServices == nil {
                    SettingsFootnote("Services available in your region are checked on the first refresh.")
                }

                SettingsSectionHeader(title: "New This Week")
                SettingsGroupCard {
                    ForEach(Array(store.availableServices.enumerated()), id: \.element) { index, service in
                        SettingsRow(title: LocalizedStringKey("New on \(service.displayName)"),
                                    showDivider: index < store.availableServices.count - 1) {
                            Toggle("", isOn: serviceBinding(service, in: \.newServices)).labelsHidden()
                        }
                    }
                }
                .disabled(!store.enabled)
                SettingsFootnote("Titles added in the last 7 days. Each row costs 1 call every 2 days.")

                SettingsSectionHeader(title: "Usage")
                SettingsGroupCard {
                    SettingsRow(title: "Refresh Lists", subtitle: "Lists are kept on this Mac between refreshes") {
                        Picker("", selection: $store.refreshHours) {
                            Text("Every 12 hours").tag(12)
                            Text("Every day").tag(24)
                            Text("Every 2 days").tag(48)
                        }
                        .labelsHidden()
                        .frame(width: 160)
                    }
                    SettingsRow(title: "Daily Limit per Key", subtitle: "Each key stops for the day at this many calls") {
                        Picker("", selection: $budget.dailyLimit) {
                            ForEach([10, 15, 20, 25, 30], id: \.self) { Text("\($0) calls").tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }
                    SettingsRow(title: "Today", subtitle: LocalizedStringKey(estimateText)) {
                        Text("\(budget.totalCallsToday(store.keyFingerprints)) of \(budget.dailyLimit * max(store.keys.count, 1))")
                            .font(.system(size: 13, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: DS.Space.s8) {
                        if let error = store.lastError {
                            Text(error).font(.system(size: 11.5)).foregroundStyle(.orange).lineLimit(2)
                        } else if let last = store.lastRefresh {
                            Text("Last checked \(last.formatted(.relative(presentation: .named)))")
                                .font(.system(size: 11.5)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Clear Saved Lists") { store.clearCache() }
                            .buttonStyle(.settingsSecondary)
                        Button(isRefreshing ? String(localized: "Refetching…") : String(localized: "Refetch All")) {
                            Task {
                                isRefreshing = true
                                await store.refreshNow()
                                isRefreshing = false
                            }
                        }
                        .buttonStyle(.settingsSecondary)
                        .disabled(isRefreshing || !store.isActive || store.allowanceToday < store.callsPerRefresh)
                        .help("Uses \(store.callsPerRefresh) calls")
                    }
                    .padding(.horizontal, DS.Space.s12)
                    .padding(.vertical, DS.Space.s8)
                }
                SettingsFootnote("Each key allows 1,000 calls a month. With these settings refetching everything costs \(store.callsPerRefresh) calls.")

                if !store.savedLists.isEmpty {
                    SettingsSectionHeader(title: "Saved Lists")
                    SettingsGroupCard {
                        ForEach(Array(store.savedLists.enumerated()), id: \.element.id) { index, list in
                            SettingsRow(title: LocalizedStringKey(list.title),
                                        subtitle: LocalizedStringKey(listSubtitle(list)),
                                        showDivider: index < store.savedLists.count - 1) {
                                Button {
                                    Task {
                                        refetching.insert(list.id)
                                        await store.refetch(list.id)
                                        refetching.remove(list.id)
                                    }
                                } label: {
                                    if refetching.contains(list.id) { ProgressView().controlSize(.small) } else { Text("Refetch") }
                                }
                                .buttonStyle(.settingsSecondary)
                                .disabled(!refetching.isEmpty || isRefreshing || store.allowanceToday == 0)
                                .help("Fetch this list again now (1 call)")
                            }
                        }
                    }
                    SettingsFootnote("Lists refresh on their own when they're older than the refresh setting. Refetch gets one now.")
                }
            }
        }
        .onChange(of: store.enabled) { _ in changed() }
        .onChange(of: store.region) { _ in changed() }
        .onChange(of: store.splitByType) { _ in changed() }
        .onChange(of: store.topServices) { _ in changed() }
        .onChange(of: store.newServices) { _ in changed() }
    }

    // MARK: Status

    private var status: (SettingsStatus, String, String) {
        let keys = store.keys
        if keys.isEmpty {
            return (.notSetUp, String(localized: "Not set up"), String(localized: "Add your own API key to get Top 10 rows for Netflix, Prime Video, Disney+, Apple TV+ and Max"))
        }
        if let error = store.lastError, error.contains("key") {
            return (.error, String(localized: "A key was not accepted"), error)
        }
        let known = keys.compactMap { budget.quotas[$0.id] }
        let keyWord = keys.count == 1 ? String(localized: "1 key") : String(localized: "\(keys.count) keys")
        guard !known.isEmpty else {
            return (.connected, String(localized: "Connected · \(keyWord)"), String(localized: "Usage shows after the first request"))
        }
        let left = known.reduce(0) { $0 + $1.remaining }
        let granted = known.reduce(0) { $0 + $1.granted }
        var utc = Date.FormatStyle.dateTime.month(.abbreviated).day()
        utc.timeZone = TimeZone(identifier: "UTC")!
        let reset = known.compactMap(\.resetsAt).min().map { $0.formatted(utc) } ?? "—"
        return (.connected, String(localized: "Connected · \(keyWord)"),
                String(localized: "\(left) of \(granted) calls left this month · resets \(reset)"))
    }

    private func keyRow(_ key: StreamingAvailabilityStore.KeyInfo) -> some View {
        let quota = budget.quotas[key.id]
        let today = budget.callsToday(key.id)
        let detail = quota.map { String(localized: "\($0.remaining) of \($0.granted) left this month · \(today) today") }
            ?? String(localized: "\(today) calls today")
        return HStack(spacing: DS.Space.s10) {
            Image(systemName: "key.fill").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(key.masked).font(.system(size: 13, design: .monospaced))
                Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Remove") { store.removeKey(key.id); changed() }
                .buttonStyle(.settingsDestructive)
        }
        .padding(.horizontal, DS.Space.s12)
        .padding(.vertical, DS.Space.s8)
    }

    private func listSubtitle(_ list: StreamingAvailabilityStore.SavedList) -> String {
        guard let date = list.fetchedAt else { return String(localized: "Not fetched yet") }
        let age = date.formatted(.relative(presentation: .named))
        return list.count > 0 ? String(localized: "\(list.count) titles · updated \(age)") : String(localized: "Updated \(age)")
    }

    private var estimateText: String {
        let perRefresh = store.callsPerRefresh
        let perDay = Double(perRefresh) * 24 / Double(store.refreshHours)
        return String(localized: "About \(Int(perDay.rounded())) calls a day, \(Int((perDay * 30).rounded())) a month")
    }

    // MARK: Actions

    private func serviceBinding(_ service: StreamingService, in keyPath: ReferenceWritableKeyPath<StreamingAvailabilityStore, [String]>) -> Binding<Bool> {
        Binding(
            get: { store[keyPath: keyPath].contains(service.rawValue) },
            set: { on in
                var list = store[keyPath: keyPath].filter { $0 != service.rawValue }
                if on { list.append(service.rawValue) }
                store[keyPath: keyPath] = list
            }
        )
    }

    private func addKey() {
        let key = keyDraft
        guard !key.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Task {
            isAdding = true
            defer { isAdding = false }
            if let error = await store.addKey(key) {
                addMessage = (error, false)
            } else {
                keyDraft = ""
                addMessage = (String(localized: "Key added."), true)
                changed()
            }
        }
    }

    /// Settings changed: reload Home's rows shortly (debounced; only due lists cost calls).
    private func changed() {
        changeToken += 1
        let token = changeToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard token == changeToken else { return }
            NotificationCenter.default.post(name: StreamingAvailabilityStore.didUpdateNotification, object: nil)
        }
    }
}
