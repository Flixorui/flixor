//
//  MyBluraySettingsView.swift
//  FlixorMac
//
//  Settings > Integrations > MyBluray: each person's own key, what that key
//  can reach, and what MyBluray adds to the app (trailers, ratings, parents
//  guide, disc releases, the edition page and the Library section).
//

import SwiftUI
import AppKit

struct MyBluraySettingsView: View {
    @ObservedObject private var store = MyBluraySettingsStore.shared

    @State private var keyDraft = ""
    @State private var isEditingKey = false
    @State private var isSaving = false
    @State private var keyMessage: (text: String, success: Bool)?
    @State private var cacheSize: Int64 = 0

    private static let portalURL = URL(string: "https://mybluray.devhomelab.app")!

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            accountCard
            SettingsFootnote("Each person on this Mac uses their own key. Keys are kept in the Keychain, per profile.")

            if case .valid(let access) = store.keyStatus {
                accessSection(access)
            }

            Group {
                trailersSection
                ratingsSection
                guideSection
                physicalSection
                editionSection
                librarySection
            }
            .disabled(!store.isActive)
            .opacity(store.isActive ? 1 : 0.55)

            storageSection
        }
        .task {
            cacheSize = MyBlurayService.shared.cacheSizeOnDisk
            await store.checkKeyIfNeeded()
        }
    }

    // MARK: - Account

    private var accountCard: some View {
        SettingsGroupCard {
            statusRow
            divider
            if store.hasKey && !isEditingKey {
                savedKeyRow
            } else {
                keyEntry
            }
            divider
            SettingsRow(
                title: "Use MyBluray",
                subtitle: store.hasKey ? "Turn off to hide everything below without removing your key" : "Add a key first",
                showDivider: false
            ) {
                Toggle("", isOn: store.hasKey ? $store.enabled : .constant(false))
                    .labelsHidden()
                    .disabled(!store.hasKey)
            }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch store.keyStatus {
        case .none:
            SettingsStatusRow(.notSetUp, title: String(localized: "Not set up"),
                              subtitle: String(localized: "Add your key from the MyBluray portal"))
        case .unchecked, .checking:
            SettingsStatusRow(.notSetUp, title: String(localized: "Checking your key…")) {
                ProgressView().controlSize(.small)
            }
        case .valid:
            if store.enabled {
                SettingsStatusRow(.connected, title: String(localized: "Connected"),
                                  subtitle: String(localized: "Trailers, ratings, parents guides and disc releases are on"))
            } else {
                SettingsStatusRow(.notSetUp, title: String(localized: "Off"),
                                  subtitle: String(localized: "Your key is saved. Turn on MyBluray below."))
            }
        case .invalid(let message):
            SettingsStatusRow(.error, title: String(localized: "Key not accepted"), subtitle: message) {
                Button("Change Key") { startEditing() }.buttonStyle(.settingsSecondary)
            }
        case .unreachable(let message):
            SettingsStatusRow(.warning, title: String(localized: "Couldn't check your key"), subtitle: message) {
                Button("Try Again") { Task { await store.checkKey() } }.buttonStyle(.settingsSecondary)
            }
        }
    }

    private var savedKeyRow: some View {
        SettingsRow(title: "API Key", subtitle: LocalizedStringKey(store.maskedKey)) {
            HStack(spacing: DS.Space.s6) {
                Button("Change") { startEditing() }
                    .buttonStyle(.settingsSecondary)
                Button("Remove") {
                    Task {
                        await store.removeKey()
                        cacheSize = MyBlurayService.shared.cacheSizeOnDisk
                        keyMessage = nil
                    }
                }
                .buttonStyle(.settingsDestructive)
            }
        }
        .padding(.bottom, -1) // the row's own divider sits under the card divider
    }

    private var keyEntry: some View {
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            Text(store.hasKey ? "New API Key" : "API Key").font(.system(size: 13))
            HStack(spacing: DS.Space.s8) {
                SecureField("mbr_…", text: $keyDraft)
                    .textFieldStyle(.settings)
                    .onSubmit(saveKey)
                    .onChange(of: keyDraft) { _ in
                        if keyMessage?.success == false { keyMessage = nil }
                    }
                Button(isSaving ? String(localized: "Checking…") : String(localized: "Save"), action: saveKey)
                    .buttonStyle(.settingsSecondary)
                    .disabled(isSaving || keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                if store.hasKey {
                    Button("Cancel") {
                        isEditingKey = false
                        keyDraft = ""
                        keyMessage = nil
                    }
                    .buttonStyle(.settingsSecondary)
                    .disabled(isSaving)
                }
            }
            HStack(spacing: DS.Space.s4) {
                if let keyMessage {
                    Text(keyMessage.text)
                        .foregroundStyle(keyMessage.success ? Color.green : SettingsChrome.destructive)
                } else {
                    Text("Create a key at").foregroundStyle(.secondary)
                    Link("mybluray.devhomelab.app ↗", destination: Self.portalURL)
                }
            }
            .font(.system(size: 11.5))
        }
        .padding(.horizontal, DS.Space.s12)
        .padding(.vertical, DS.Space.s10)
    }

    private func startEditing() {
        keyDraft = ""
        keyMessage = nil
        isEditingKey = true
    }

    private func saveKey() {
        let draft = keyDraft
        guard !draft.trimmingCharacters(in: .whitespaces).isEmpty, !isSaving else { return }
        Task {
            isSaving = true
            defer { isSaving = false }
            if let error = await store.saveKey(draft) {
                keyMessage = (error, false)
            } else {
                keyDraft = ""
                keyMessage = nil
                isEditingKey = false
                cacheSize = MyBlurayService.shared.cacheSizeOnDisk
            }
        }
    }

    // MARK: - What the key can reach

    private func accessSection(_ access: MyBlurayAccess) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            SettingsSectionHeader(title: "What Your Key Can Reach")
            SettingsGroupCard {
                accessRow(access, MyBlurayAccess.appleTV, icon: "tv.fill", color: Color(hex: "1C1C1E"),
                          title: "Apple TV", subtitle: "Trailers in up to 4K HDR, ratings and age guidance")
                accessRow(access, MyBlurayAccess.imdb, icon: "person.2.fill", color: Color(hex: "C99A06"),
                          title: "IMDb", subtitle: "Parents guide")
                accessRow(access, MyBlurayAccess.letterboxd, icon: "circle.grid.2x1.fill", color: Color(hex: "00A846"),
                          title: "Letterboxd", subtitle: "Ratings")
                accessRow(access, MyBlurayAccess.justWatch, icon: "play.rectangle.fill", color: Color(hex: "A88A00"),
                          title: "JustWatch", subtitle: "Ratings, age ratings and clips")
                accessRow(access, MyBlurayAccess.bluray, icon: "opticaldisc", color: Color(hex: "0077B6"),
                          title: "Blu-ray.com", subtitle: "Disc releases, specs, reviews and screenshots")
                accessRow(access, MyBlurayAccess.collection, icon: "square.stack.3d.up.fill", color: Color(hex: "5E5CE6"),
                          title: "Your Collection",
                          subtitle: access.state(MyBlurayAccess.collection) == .no
                            ? "Attach your Blu-ray.com login to this key in the portal"
                            : "Your Blu-ray.com collection and wishlist",
                          showDivider: false)
            }
            HStack(spacing: DS.Space.s6) {
                Text("Change what a key can reach in the").foregroundStyle(.secondary)
                Link("portal ↗", destination: Self.portalURL)
                Spacer(minLength: 0)
                Button("Check Again") { Task { await store.checkKey() } }
                    .buttonStyle(.settingsSecondary)
            }
            .font(.system(size: 11.5))
            .padding(.horizontal, DS.Space.s10)
            .padding(.top, -DS.Space.s8)
        }
    }

    private func accessRow(_ access: MyBlurayAccess, _ id: String, icon: String, color: Color,
                           title: String, subtitle: String, showDivider: Bool = true) -> some View {
        SettingsRow(icon: icon, iconColor: color, title: LocalizedStringKey(title),
                    subtitle: LocalizedStringKey(subtitle), showDivider: showDivider) {
            AccessBadge(state: access.state(id))
        }
    }

    // MARK: - What to show

    private var trailersSection: some View {
        optionSection("Trailers", [
            .init(.appleTrailers, "Apple TV trailers first", "YouTube trailers are used when Apple TV has none"),
            .init(.highQualityTrailers, "Best quality", "The full-screen trailer plays in up to 4K HDR. The Details hero stays at 1080p and hover previews at 720p."),
            .init(.bonusVideos, "Bonus videos", "Featurettes and clips on Details. Each title takes a larger request."),
        ])
    }

    private var ratingsSection: some View {
        optionSection("Ratings", [
            .init(.ratings, "Ratings from MyBluray",
                  "IMDb, Rotten Tomatoes, Letterboxd and TMDB scores on Details. Choose which ratings show, and the source of each, in Settings → Details."),
        ])
    }

    private var guideSection: some View {
        optionSection("Parents Guide", [
            .init(.ageRatings, "Age ratings", "Certificates and the reasons given for them"),
            .init(.commonSense, "Common Sense Media", "Recommended age, and scores for violence, language and more"),
            .init(.imdbGuide, "IMDb parents guide", "How strong each category is, voted by IMDb users"),
            .init(.guideDescriptions, "Written descriptions", "What happens, listed under each category"),
            .init(.revealSpoilers, "Show spoilers", "Otherwise descriptions marked as spoilers stay hidden until you click them"),
        ])
    }

    private var physicalSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            SettingsSectionHeader(title: "Physical Releases")
            SettingsGroupCard {
                SettingsRow(title: "Show on Details", subtitle: "Blu-ray and 4K editions of the film you're viewing") {
                    Toggle("", isOn: store.binding(.physicalReleases)).labelsHidden()
                }
                SettingsRow(title: "Country", subtitle: "Editions released in this market") {
                    Picker("", selection: $store.discCountry) {
                        Text("Automatic (\(MyBluraySettingsStore.localRegion))").tag("auto")
                        Text("All countries").tag("all")
                        Divider()
                        ForEach(MyBluraySettingsStore.discCountries, id: \.code) { country in
                            Text(country.name).tag(country.code)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }
                .disabled(!store.isChosen(.physicalReleases))
                .opacity(store.isChosen(.physicalReleases) ? 1 : 0.5)
                optionRow(.init(.blurayFormat, "Blu-ray", nil))
                optionRow(.init(.uhdFormat, "4K Ultra HD", nil))
                optionRow(.init(.boxSets, "Box sets", "Editions that bundle several films"))
                optionRow(.init(.quickAdd, "Quick add to collection", collectionSubtitle("A button on each edition to add it to your collection or wishlist")),
                          showDivider: false)
            }
            if store.discCountry == "all" {
                SettingsFootnote("Popular films can have hundreds of editions worldwide, so the first look takes longer.")
            }
        }
    }

    private var editionSection: some View {
        optionSection("Edition Page", [
            .init(.editionSpecs, "Specs", "Video, audio, subtitles, discs and packaging"),
            .init(.editionScores, "Review scores", "Blu-ray.com and community scores for picture, sound and extras"),
            .init(.editionScreenshots, "Screenshots", "Frames taken from the disc"),
            .init(.editionArtwork, "Artwork", "Covers, slipcovers and packaging"),
            .init(.editionDigitalCopy, "Digital copy", "Whether a code is included, and where it redeems"),
            .init(.editionPrice, "Price", "Current price and a link to buy"),
            .init(.editionLinks, "Links", "Blu-ray.com, IMDb and other sites"),
        ], footnote: "Opens when you click an edition on Details.")
    }

    private var librarySection: some View {
        optionSection("Library", [
            .init(.librarySection, "Physical collection",
                  collectionSubtitle("Your owned discs and wishlist as a Library section, matched to your Plex titles")),
        ])
    }

    /// Adds a note when the key has no Blu-ray.com login, which these features need.
    private func collectionSubtitle(_ text: String) -> String {
        if case .valid(let access) = store.keyStatus, access.state(MyBlurayAccess.collection) == .no {
            return text + ". " + String(localized: "Needs your Blu-ray.com login on the key.")
        }
        return text
    }

    // MARK: - Storage

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            SettingsSectionHeader(title: "Storage")
            SettingsGroupCard {
                SettingsRow(title: "Saved Results",
                            subtitle: LocalizedStringKey(cacheSize == 0
                                ? String(localized: "Nothing saved yet")
                                : ByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .file)
                                    + " · " + String(localized: "kept so titles you open again load at once"))) {
                    Button("Clear") {
                        Task {
                            await MyBlurayService.shared.clearCache()
                            cacheSize = MyBlurayService.shared.cacheSizeOnDisk
                        }
                    }
                    .buttonStyle(.settingsSecondary)
                    .disabled(cacheSize == 0)
                }
                SettingsRow(title: "Reset Display Choices", subtitle: "Turns every option above back to its default. Keeps your key.",
                            showDivider: false) {
                    Button("Reset") { store.resetDisplaySettings() }
                        .buttonStyle(.settingsSecondary)
                }
            }
        }
    }

    // MARK: - Option rows

    private struct OptionItem {
        let option: MyBlurayOption
        let title: String
        let subtitle: String?

        init(_ option: MyBlurayOption, _ title: String, _ subtitle: String?) {
            self.option = option
            self.title = title
            self.subtitle = subtitle
        }
    }

    private func optionSection(_ title: LocalizedStringKey, _ items: [OptionItem], footnote: LocalizedStringKey? = nil) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            SettingsSectionHeader(title: title)
            SettingsGroupCard {
                ForEach(Array(items.enumerated()), id: \.element.option) { index, item in
                    optionRow(item, showDivider: index < items.count - 1)
                }
            }
            if let footnote { SettingsFootnote(footnote) }
        }
    }

    private func optionRow(_ item: OptionItem, showDivider: Bool = true) -> some View {
        SettingsRow(title: LocalizedStringKey(item.title),
                    subtitle: item.subtitle.map { LocalizedStringKey($0) },
                    showDivider: showDivider) {
            Toggle("", isOn: store.binding(item.option)).labelsHidden()
        }
        .disabled(store.isBlocked(item.option))
        .opacity(store.isBlocked(item.option) ? 0.5 : 1)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.horizontal, DS.Space.s12)
    }
}

// MARK: - Access Badge

private struct AccessBadge: View {
    let state: MyBlurayAccess.State

    var body: some View {
        HStack(spacing: DS.Space.s4) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
            Text(label)
        }
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(color)
    }

    private var label: String {
        switch state {
        case .yes: return String(localized: "Included")
        case .no: return String(localized: "Not on this key")
        case .unknown: return String(localized: "Couldn't check")
        }
    }

    private var symbol: String {
        switch state {
        case .yes: return "checkmark"
        case .no: return "minus"
        case .unknown: return "questionmark"
        }
    }

    private var color: Color {
        switch state {
        case .yes: return Color(red: 0.19, green: 0.82, blue: 0.35)
        case .no: return .secondary
        case .unknown: return .orange
        }
    }
}
