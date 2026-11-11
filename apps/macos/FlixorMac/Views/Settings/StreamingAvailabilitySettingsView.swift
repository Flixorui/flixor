//
//  StreamingAvailabilitySettingsView.swift
//  FlixorMac
//
//  Settings > Integrations > Top 10 Lists: your FlixPatrol APIs (tried first
//  for Top 10 rows) and Streaming Availability keys ("New on" rows and the
//  Top 10 fallback), which rows appear on Home, the region, and the call
//  budget that keeps Streaming Availability inside its monthly quota.
//

import SwiftUI
import AppKit

struct StreamingAvailabilitySettingsView: View {
    @ObservedObject private var store = StreamingAvailabilityStore.shared
    @ObservedObject private var budget = StreamingAvailabilityBudget.shared

    @State private var keyDraft = ""
    @State private var flixPatrolURLDraft = ""
    @State private var flixPatrolKeyDraft = ""
    @State private var isAddingFlixPatrol = false
    @State private var flixPatrolMessage: (String, Bool)?
    @State private var isAdding = false
    @State private var addMessage: (String, Bool)?
    @State private var isRefreshing = false
    @State private var refetching: Set<String> = []
    @State private var changeToken = 0

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            SettingsSectionHeader(title: "FlixPatrol")
            SettingsGroupCard {
                SettingsStatusRow(flixPatrolStatus.0, title: flixPatrolStatus.1, subtitle: flixPatrolStatus.2)
                ForEach(Array(store.flixPatrolSources.enumerated()), id: \.element.id) { index, source in
                    divider
                    flixPatrolRow(source, index: index)
                }
                divider
                flixPatrolAddForm
            }
            SettingsFootnote("Used first for Top 10 rows, with no call limit. Add more than one and the next is used when one fails.")

            SettingsSectionHeader(title: "Streaming Availability")
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
            SettingsFootnote("Used for New This Week rows, and for Top 10 lists FlixPatrol doesn't have.")

            if store.hasAnySource {
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
                    SettingsRow(title: "Movies and Shows", subtitle: store.splitByType ? "Two rows per service" : "One mixed row per service") {
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
                if (store.hasFlixPatrol && store.flixPatrolServices == nil) || (store.hasKey && store.regionServices == nil) {
                    SettingsFootnote("Services available in your region are checked on the first refresh.")
                }

                if store.hasKey {
                    SettingsSectionHeader(title: "New This Week")
                    SettingsGroupCard {
                        ForEach(Array(store.newRowServices.enumerated()), id: \.element) { index, service in
                            SettingsRow(title: LocalizedStringKey("New on \(service.displayName)"),
                                        showDivider: index < store.newRowServices.count - 1) {
                                Toggle("", isOn: serviceBinding(service, in: \.newServices)).labelsHidden()
                            }
                        }
                    }
                    .disabled(!store.enabled)
                    SettingsFootnote("Titles added in the last 7 days, from Streaming Availability. Each row costs 1 call every 2 days.")
                }

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
                    if store.hasKey {
                        SettingsRow(title: "Daily Limit per Key", subtitle: "Each Streaming Availability key stops for the day at this many calls") {
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
                    }
                    HStack(spacing: DS.Space.s8) {
                        if let error = store.flixPatrolError ?? store.lastError {
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
                        .help(store.callsPerRefresh > 0 ? "Uses \(store.callsPerRefresh) Streaming Availability calls" : "FlixPatrol lists are free to refetch")
                    }
                    .padding(.horizontal, DS.Space.s12)
                    .padding(.vertical, DS.Space.s8)
                }
                if store.hasKey {
                    SettingsFootnote("Each Streaming Availability key allows 1,000 calls a month. With these settings refetching everything costs \(store.callsPerRefresh) calls; FlixPatrol lists are free.")
                } else {
                    SettingsFootnote("FlixPatrol lists are checked every 6 hours at most, or at the refresh setting if that's sooner.")
                }

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
                                .disabled(!refetching.isEmpty || isRefreshing || (list.usesBudget && store.allowanceToday == 0))
                                .help(list.usesBudget ? "Fetch this list again now (1 call)" : "Fetch this list again now (free)")
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

    // MARK: FlixPatrol

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.horizontal, DS.Space.s12)
    }

    private var flixPatrolStatus: (SettingsStatus, String, String) {
        let count = store.flixPatrolSources.count
        if count == 0 {
            return (.notSetUp, String(localized: "Not set up"),
                    String(localized: "Add a FlixPatrol API URL and key for Top 10 rows, including Paramount+, Hulu, Starz and JioHotstar"))
        }
        if let error = store.flixPatrolError {
            return (.error, String(localized: "Couldn't reach FlixPatrol"), error)
        }
        let word = count == 1 ? String(localized: "1 API") : String(localized: "\(count) APIs")
        let services = store.flixPatrolServices.map { set in
            StreamingService.allCases.filter { set.contains($0.rawValue) }.map(\.displayName).joined(separator: ", ")
        }
        let detail: String
        if let services, services.isEmpty {
            detail = String(localized: "No charts for this region")
        } else {
            detail = services.map { String(localized: "Charts here: \($0)") } ?? String(localized: "Used first for Top 10 rows")
        }
        return (.connected, String(localized: "Connected · \(word)"), detail)
    }

    private func flixPatrolRow(_ source: FlixPatrolSource, index: Int) -> some View {
        HStack(spacing: DS.Space.s10) {
            Image(systemName: "link").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(source.host).font(.system(size: 13, weight: .medium))
                Text(index == 0 ? "\(source.maskedKey) · tried first" : "\(source.maskedKey) · fallback \(index)")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if index > 0 {
                Button("Use First") { store.preferFlixPatrolSource(source.id); changed() }
                    .buttonStyle(.settingsSecondary)
            }
            Button("Remove") { store.removeFlixPatrolSource(source.id); changed() }
                .buttonStyle(.settingsDestructive)
        }
        .padding(.horizontal, DS.Space.s12)
        .padding(.vertical, DS.Space.s8)
    }

    private var flixPatrolAddForm: some View {
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            Text(store.flixPatrolSources.isEmpty ? "Add FlixPatrol API" : "Add Another FlixPatrol API").font(.system(size: 13))
            TextField(String(localized: "API URL, e.g. https://example.com/v2"), text: $flixPatrolURLDraft)
                .textFieldStyle(.settings)
                .onSubmit(addFlixPatrol)
            HStack(spacing: DS.Space.s8) {
                SecureField(String(localized: "API key"), text: $flixPatrolKeyDraft)
                    .textFieldStyle(.settings)
                    .onSubmit(addFlixPatrol)
                Button(isAddingFlixPatrol ? String(localized: "Checking…") : String(localized: "Add"), action: addFlixPatrol)
                    .buttonStyle(.settingsSecondary)
                    .disabled(isAddingFlixPatrol
                              || flixPatrolURLDraft.trimmingCharacters(in: .whitespaces).isEmpty
                              || flixPatrolKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let flixPatrolMessage {
                Text(flixPatrolMessage.0)
                    .font(.system(size: 11.5))
                    .foregroundStyle(flixPatrolMessage.1 ? Color.green : SettingsChrome.destructive)
            } else {
                Text("The base URL of a FlixPatrol JSON API (v2) and its key.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, DS.Space.s12)
        .padding(.vertical, DS.Space.s10)
    }

    private func addFlixPatrol() {
        let url = flixPatrolURLDraft
        let key = flixPatrolKeyDraft
        guard !url.trimmingCharacters(in: .whitespaces).isEmpty, !key.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Task {
            isAddingFlixPatrol = true
            defer { isAddingFlixPatrol = false }
            if let error = await store.addFlixPatrolSource(url: url, key: key) {
                flixPatrolMessage = (error, false)
            } else {
                flixPatrolURLDraft = ""
                flixPatrolKeyDraft = ""
                flixPatrolMessage = (String(localized: "FlixPatrol API added."), true)
                changed()
            }
        }
    }

    // MARK: Status

    private var status: (SettingsStatus, String, String) {
        let keys = store.keys
        if keys.isEmpty {
            return (.notSetUp, String(localized: "Not set up"), String(localized: "Add your own Movie of the Night key for New This Week rows and Top 10 fallback"))
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
        return list.count > 0 ? String(localized: "\(list.count) titles · \(list.source) · updated \(age)")
                              : String(localized: "\(list.source) · updated \(age)")
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
