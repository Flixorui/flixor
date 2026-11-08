//
//  StreamSelectionSettings.swift
//  FlixorMac
//
//  Settings for what pressing Play on addon content does, with a rule editor and live preview.
//

import SwiftUI

@MainActor
final class StreamSelectionSettingsStore: ObservableObject {
    @Published var action: StremioPlayAction {
        didSet { UserDefaults.standard.stremioPlayAction = action }
    }
    @Published var rules: StreamSelectionRules {
        didSet { UserDefaults.standard.stremioStreamRules = rules }
    }
    @Published var timeLimit: Int {
        didSet { UserDefaults.standard.stremioAutoPickTimeLimit = timeLimit }
    }

    init() {
        action = UserDefaults.standard.stremioPlayAction
        rules = UserDefaults.standard.stremioStreamRules
        timeLimit = UserDefaults.standard.stremioAutoPickTimeLimit
    }
}

/// Row for the Playback group: the Play action, plus the time limit for the automatic ones.
struct StreamPlayActionRows: View {
    @ObservedObject var store: StreamSelectionSettingsStore

    private static let timeLimits = [3, 5, 8, 10, 15, 30]

    private var limitChoices: [Int] {
        Self.timeLimits.contains(store.timeLimit) ? Self.timeLimits : (Self.timeLimits + [store.timeLimit]).sorted()
    }

    var body: some View {
        SettingsRow(
            icon: "bolt.fill",
            iconColor: .yellow,
            title: "When I press Play on addon content",
            subtitle: store.action.settingsSubtitle
        ) {
            Picker("", selection: $store.action) {
                ForEach(StremioPlayAction.allCases) { action in
                    Text(action.displayName).tag(action)
                }
            }
            .labelsHidden()
            .frame(width: 180)
            .accessibilityLabel("When I press Play on addon content")
        }

        if store.action.isAutomatic {
            SettingsRow(
                icon: "timer",
                iconColor: .orange,
                title: "Wait for Addons",
                subtitle: "Longest to wait before deciding with the sources that have arrived"
            ) {
                Picker("", selection: $store.timeLimit) {
                    ForEach(limitChoices, id: \.self) { seconds in
                        Text("\(seconds) seconds").tag(seconds)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
                .accessibilityLabel("Time limit for waiting on addons")
            }
        }
    }
}

private extension StremioPlayAction {
    var settingsSubtitle: String {
        switch self {
        case .showSources:
            return "Always open the list of sources"
        case .playBest:
            return "Start the best playable source. Hold Option when pressing Play to see the list."
        case .matchRules:
            return "Start the best source that fits your rules, or show the list if none does"
        }
    }
}

/// The "Match my rules" editor.
struct StreamRulesEditor: View {
    @ObservedObject var store: StreamSelectionSettingsStore
    let addons: [StremioAddonSummary]

    private static let resolutionLimits = [2160, 1080, 720, 480]

    /// Example release names for the live preview.
    private static let examples = [
        "Movie 2024 2160p WEB-DL DV HDR x265",
        "Movie 2024 1080p BluRay x264 DTS",
        "Movie 2024 720p WEBRip x265",
        "Movie 2024 HDCAM 720p x264",
        "Movie.2024.HDTS.1080p.x264",
        "Movie 2024 TS 480p",
    ]

    private var matcher: StreamRuleMatcher? {
        // A short budget: the preview runs on the main actor, on six short names.
        try? StreamRuleMatcher(rules: store.rules, matchingBudget: 0.05)
    }

    private var streamAddons: [StremioAddonSummary] {
        addons.filter(\.streamCapable)
    }

    /// A preferred addon that has been removed reads as no preference.
    private var preferredAddon: Binding<String?> {
        Binding(
            get: {
                let id = store.rules.preferredAddonId
                return streamAddons.contains { $0.installationId == id } ? id : nil
            },
            set: { store.rules.preferredAddonId = $0 }
        )
    }

    var body: some View {
        SettingsGroupCard {
            VStack(alignment: .leading, spacing: DS.Space.itemGap) {
                includeField
                excludeField
                Divider()
                limitPickers
                Divider()
                preview
            }
            .padding(DS.Space.itemGap)
        }
    }

    private var includeField: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            HStack {
                Text("Include")
                    .flixorFont(.callout, weight: .medium)
                Spacer()
                Picker("", selection: $store.rules.includeIsRegex) {
                    Text("Words").tag(false)
                    Text("Regular Expression").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                .accessibilityLabel("Include field type")
            }

            TextField("2160p|4K", text: $store.rules.include)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
                .accessibilityLabel("Include")

            if matcher == nil {
                Text("This pattern isn't valid, or repeats inside a repeat like (a+)+ and could hang, so Play will show the list of sources.")
                    .flixorFont(.caption)
                    .foregroundStyle(.red)
            } else {
                Text(store.rules.includeIsRegex
                     ? "Sources must match this pattern (not case-sensitive). Leave empty to allow any."
                     : "Sources must contain one of these words, separated by | or commas. Leave empty to allow any.")
                    .flixorFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var excludeField: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            Text("Exclude")
                .flixorFont(.callout, weight: .medium)
            TextField("CAM|TS|HDTS", text: $store.rules.exclude)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
                .accessibilityLabel("Exclude")
            Text("Sources containing any of these whole words are skipped.")
                .flixorFont(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var limitPickers: some View {
        VStack(alignment: .leading, spacing: DS.Space.controlGap) {
            HStack {
                Text("Preferred Addon")
                    .flixorFont(.callout, weight: .medium)
                Spacer()
                Picker("", selection: preferredAddon) {
                    Text("Any addon").tag(String?.none)
                    ForEach(streamAddons) { addon in
                        Text(addon.name).tag(String?.some(addon.installationId))
                    }
                }
                .labelsHidden()
                .frame(width: 220)
                .accessibilityLabel("Preferred addon")
            }

            HStack {
                Text("Highest Resolution")
                    .flixorFont(.callout, weight: .medium)
                Spacer()
                Picker("", selection: $store.rules.maxResolution) {
                    Text("No limit").tag(Int?.none)
                    ForEach(Self.resolutionLimits, id: \.self) { resolution in
                        Text(resolution == 2160 ? "4K" : "\(resolution)p").tag(Int?.some(resolution))
                    }
                }
                .labelsHidden()
                .frame(width: 220)
                .accessibilityLabel("Highest resolution")
            }
        }
    }

    @ViewBuilder private var preview: some View {
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            Text("Preview")
                .flixorFont(.callout, weight: .medium)

            if let matcher {
                ForEach(Self.examples, id: \.self) { example in
                    previewRow(
                        example,
                        verdict: matcher.verdict(text: example, resolution: StremioSourceRanking.resolutionBucket(text: example))
                    )
                }
            } else {
                Text("Fix the pattern above to see which sources it matches.")
                    .flixorFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func previewRow(_ name: String, verdict: StreamRuleVerdict) -> some View {
        HStack(spacing: DS.Space.controlGap) {
            Image(systemName: verdict.isMatch ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(verdict.isMatch ? Color.green : Color.secondary)
                .accessibilityHidden(true)
            Text(name)
                .flixorFont(.caption)
                .lineLimit(1)
            Spacer()
            Text(verdict.previewLabel)
                .flixorFont(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private extension StreamRuleVerdict {
    var previewLabel: String {
        switch self {
        case .match: return "Matches"
        case .timedOut: return "Too slow to check"
        case .missingInclude: return "No include match"
        case .excluded(let word): return "Excluded: \(word)"
        case .aboveResolutionLimit: return "Above limit"
        }
    }
}
