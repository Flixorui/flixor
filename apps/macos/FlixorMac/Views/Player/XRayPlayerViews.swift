//
//  XRayPlayerViews.swift
//  FlixorMac
//
//  X-Ray in the player: the "In this scene" strip above the seek bar (with the
//  controls), the X-Ray button, the side panel (X) and the analysed band on the
//  seek bar. Colours follow DesignTokens' rules: neutral chrome, the accent only for
//  what's on or selected.
//

import SwiftUI

// MARK: - Strip

struct XRayStrip: View {
    @ObservedObject var xray: XRayController
    let onOpen: (Int?) -> Void
    @Environment(\.flixorTheme) private var theme

    private static let maxChips = 3

    var body: some View {
        let content = stripContent
        if !content.people.isEmpty || content.status != nil {
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                Text(content.label)
                    .font(.flixor(.micro, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.6))
                HStack(spacing: DS.Space.s8) {
                    ForEach(content.people.prefix(Self.maxChips)) { member in
                        XRayChip(member: member) { onOpen(member.id) }
                    }
                    if content.people.count > Self.maxChips {
                        Button { onOpen(nil) } label: {
                            Text("+\(content.people.count - Self.maxChips)")
                                .font(.flixor(.caption, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(minWidth: 40, minHeight: 40)
                                .background(Capsule().fill(Color.black.opacity(0.45)))
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .help("Everyone in this scene")
                    }
                    if let status = content.status {
                        XRayStatusLabel(text: status, isWorking: true)
                    }
                }
            }
            .transition(.opacity)
        }
    }

    private var stripContent: (label: LocalizedStringKey, people: [XRayCastMember], status: LocalizedStringKey?) {
        switch xray.state {
        case .unavailable:
            return ("", [], nil)
        case .preparing:
            return ("Cast", Array(xray.cast.prefix(Self.maxChips)), "X-Ray getting ready…")
        case .working:
            if !xray.isPlayheadCovered {
                return ("Cast", Array(xray.cast.prefix(Self.maxChips)), "Analysing this part…")
            }
            return ("In this scene", xray.scenePeople, nil)
        }
    }
}

private struct XRayChip: View {
    let member: XRayCastMember
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s8) {
                XRayPhoto(member: member, size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(member.name)
                        .font(.flixor(.caption, weight: .semibold))
                        .foregroundStyle(.white)
                    if let character = member.character {
                        Text(character)
                            .font(.flixor(.micro))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
                .lineLimit(1)
            }
            .padding(.leading, DS.Space.s4)
            .padding(.trailing, DS.Space.s12)
            .padding(.vertical, DS.Space.s4)
            .background(Capsule().fill(Color.black.opacity(isHovered ? 0.6 : 0.45)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(isHovered ? 0.3 : 0.12), lineWidth: 1))
            .fixedSize()
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("\(member.name) in X-Ray")
        .accessibilityLabel(Text(member.character.map { "\(member.name), \($0)" } ?? member.name))
    }
}

struct XRayPhoto: View {
    let member: XRayCastMember
    let size: CGFloat
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.1))
            if let url = TMDBImageURL.url(member.profilePath, size: .w185) {
                CachedAsyncImage(url: url, maxPixelSize: Int(size * 3))
                    .aspectRatio(contentMode: .fill)
            } else {
                Text(member.name.split(separator: " ").compactMap(\.first).prefix(2).map(String.init).joined())
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

private struct XRayStatusLabel: View {
    let text: LocalizedStringKey
    let isWorking: Bool

    var body: some View {
        HStack(spacing: DS.Space.s6) {
            if isWorking {
                ProgressView().controlSize(.mini).tint(.white)
            }
            Text(text)
                .font(.flixor(.caption))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

// MARK: - Button

struct XRayButton: View {
    let isOn: Bool
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        Button(action: action) {
            Text("X-Ray")
                .font(.flixor(.caption, weight: .bold))
                .foregroundStyle(isOn ? .black : .white)
                .padding(.horizontal, DS.Space.s8)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: DS.Radius.r6).fill(isOn ? Color.white : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.r6).strokeBorder(Color.white.opacity(isOn ? 0 : 0.7), lineWidth: 1.5))
                .frame(height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.1 : 1.0)
        .onHover { hovering in withAnimation(DS.Motion.standard) { isHovered = hovering } }
        .help("X-Ray: who's in this scene (X)")
    }
}

// MARK: - Panel

struct XRayPanel: View {
    @ObservedObject var xray: XRayController
    @ObservedObject var viewModel: PlayerViewModel
    let focusedPerson: Int?
    let onClose: () -> Void

    @State private var tab: Tab = .scene
    @Environment(\.flixorTheme) private var theme

    enum Tab: Hashable { case scene, cast, scenes }

    var body: some View {
        HStack {
            Spacer()
            VStack(alignment: .leading, spacing: 0) {
                header
                tabs
                Divider().background(Color.white.opacity(0.1))
                ScrollViewReader { proxy in
                    ScrollView {
                        Group {
                            switch tab {
                            case .scene: sceneTab
                            case .cast: castTab
                            case .scenes: scenesTab(proxy: proxy)
                            }
                        }
                        .padding(DS.Space.s12)
                    }
                }
                Divider().background(Color.white.opacity(0.1))
                footer
            }
            .frame(width: 340)
            .frame(maxHeight: .infinity)
            .background(theme.playerPanelBackground())
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r12))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.r12).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
            .padding(.trailing, DS.Space.s20)
            .padding(.top, 72)
            .padding(.bottom, 132)
        }
    }

    private var header: some View {
        HStack {
            Text("X-Ray")
                .font(.flixor(.bodyLarge, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.flixorIcon(DS.Icon.xs, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close (X)")
        }
        .padding(.horizontal, DS.Space.s16)
        .padding(.top, DS.Space.s12)
        .padding(.bottom, DS.Space.s8)
    }

    private var tabs: some View {
        HStack(spacing: DS.Space.s4) {
            tabButton("In this scene", .scene)
            tabButton("All cast", .cast)
            tabButton("Scenes", .scenes)
        }
        .padding(.horizontal, DS.Space.s12)
        .padding(.bottom, DS.Space.s8)
    }

    private func tabButton(_ title: LocalizedStringKey, _ value: Tab) -> some View {
        Button { tab = value } label: {
            Text(title)
                .font(.flixor(.caption, weight: tab == value ? .semibold : .regular))
                .foregroundStyle(tab == value ? .white : .white.opacity(0.6))
                .padding(.horizontal, DS.Space.s10)
                .padding(.vertical, DS.Space.s4)
                .background(Capsule().fill(Color.white.opacity(tab == value ? 0.16 : 0)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: In this scene

    @ViewBuilder
    private var sceneTab: some View {
        VStack(alignment: .leading, spacing: DS.Space.s8) {
            if let scene = xray.currentScene {
                Text(sceneTitle(scene))
                    .font(.flixor(.caption))
                    .foregroundStyle(.white.opacity(0.6))
                let people = xray.scenePeople
                if people.isEmpty {
                    emptyNote("No one recognised in this scene.")
                } else {
                    ForEach(people) { member in
                        personRow(member, detail: nil, highlighted: member.id == focusedPerson)
                    }
                }
            } else if xray.isPlayheadCovered {
                emptyNote("No one recognised here.")
            } else {
                emptyNote(xray.state == .preparing ? "X-Ray is getting ready…" : "Analysing this part of the film…")
            }
        }
    }

    // MARK: All cast

    @ViewBuilder
    private var castTab: some View {
        let seen = xray.seenCast
        let seenIds = Set(seen.map(\.member.id))
        VStack(alignment: .leading, spacing: DS.Space.s8) {
            if !seen.isEmpty {
                sectionLabel("Seen so far · most screen time first")
                ForEach(seen, id: \.member.id) { entry in
                    personRow(entry.member, detail: screenTime(entry.seconds), highlighted: entry.member.id == focusedPerson)
                }
            }
            let rest = xray.cast.filter { !seenIds.contains($0.id) }
            if !rest.isEmpty {
                sectionLabel(seen.isEmpty ? "Cast" : "Not seen yet")
                    .padding(.top, seen.isEmpty ? 0 : DS.Space.s8)
                ForEach(rest) { member in
                    personRow(member, detail: nil, highlighted: false)
                        .opacity(0.6)
                }
            }
        }
    }

    // MARK: Scenes

    private func scenesTab(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if xray.scenes.isEmpty {
                emptyNote("Scenes appear here as X-Ray works through the film.")
            }
            ForEach(Array(xray.scenes.enumerated()), id: \.element.id) { index, scene in
                let isCurrent = scene == xray.currentScene
                Button { viewModel.seek(to: scene.start + 0.5) } label: {
                    HStack(spacing: DS.Space.s10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scene \(index + 1)")
                                .font(.flixor(.caption, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(verbatim: "\(Self.time(scene.start))–\(Self.time(scene.end))")
                                .font(.flixor(.micro))
                                .monospacedDigit()
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        Spacer(minLength: DS.Space.s4)
                        HStack(spacing: -8) {
                            ForEach(xray.people(in: scene).prefix(5)) { member in
                                XRayPhoto(member: member, size: 26)
                                    .overlay(Circle().strokeBorder(Color.black.opacity(0.6), lineWidth: 1.5))
                            }
                        }
                    }
                    .padding(.horizontal, DS.Space.s8)
                    .padding(.vertical, DS.Space.s6)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.r8).fill(Color.white.opacity(isCurrent ? 0.12 : 0)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .id(scene.id)
                .help("Jump to scene \(index + 1)")
            }
        }
        .onAppear {
            if let current = xray.currentScene { proxy.scrollTo(current.id, anchor: .center) }
        }
    }

    // MARK: Pieces

    private func personRow(_ member: XRayCastMember, detail: String?, highlighted: Bool) -> some View {
        let next = xray.nextScene(with: member.id, after: viewModel.currentTime)
        return HStack(alignment: .center, spacing: DS.Space.s10) {
            XRayPhoto(member: member, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name)
                    .font(.flixor(.callout, weight: .semibold))
                    .foregroundStyle(.white)
                if let character = member.character {
                    Text(character)
                        .font(.flixor(.caption))
                        .foregroundStyle(.white.opacity(0.65))
                }
                if let detail {
                    Text(detail)
                        .font(.flixor(.micro))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .lineLimit(1)
            Spacer(minLength: DS.Space.s4)
            if let next {
                Button { viewModel.seek(to: next.start + 0.5) } label: {
                    Text("Next scene ▸")
                        .font(.flixor(.micro, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, DS.Space.s8)
                        .padding(.vertical, DS.Space.s4)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .help("Jump to \(member.name)'s next scene, at \(Self.time(next.start))")
            }
        }
        .padding(DS.Space.s6)
        .background(RoundedRectangle(cornerRadius: DS.Radius.r8).fill(Color.white.opacity(highlighted ? 0.1 : 0)))
    }

    private var footer: some View {
        HStack(spacing: DS.Space.s6) {
            switch xray.state {
            case .unavailable(let reason):
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.white.opacity(0.6))
                Text(reason)
            case .preparing:
                ProgressView().controlSize(.mini).tint(.white)
                Text("Getting ready…")
            case .working:
                if xray.wholeFile && xray.isWholeFileDone {
                    Image(systemName: "checkmark").foregroundStyle(.white.opacity(0.8))
                    Text(viewModel.item.type == "episode" ? "Ready for the whole episode" : "Ready for the whole film")
                } else if let until = xray.readyUntil {
                    ProgressView().controlSize(.mini).tint(.white)
                    Text("Ready to \(Self.time(until))")
                } else {
                    ProgressView().controlSize(.mini).tint(.white)
                    Text("Analysing this part…")
                }
            }
            Spacer()
            Text("On this Mac")
                .foregroundStyle(.white.opacity(0.45))
                .help("Faces are matched on this Mac against the cast's TMDB photos. Nothing is uploaded.")
        }
        .font(.flixor(.micro))
        .foregroundStyle(.white.opacity(0.7))
        .padding(.horizontal, DS.Space.s16)
        .padding(.vertical, DS.Space.s10)
    }

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.flixor(.micro, weight: .semibold))
            .textCase(.uppercase)
            .tracking(0.5)
            .foregroundStyle(.white.opacity(0.5))
    }

    private func emptyNote(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.flixor(.caption))
            .foregroundStyle(.white.opacity(0.6))
            .padding(.vertical, DS.Space.s8)
    }

    private func sceneTitle(_ scene: XRayScene) -> String {
        let number = xray.sceneNumber(scene).map { String(localized: "Scene \($0)") } ?? String(localized: "Scene")
        return "\(number) · \(Self.time(scene.start))–\(Self.time(scene.end))"
    }

    private func screenTime(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        return minutes >= 1 ? String(localized: "\(minutes) min on screen") : String(localized: "Under a minute on screen")
    }

    static func time(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Seek bar band

/// The analysed stretches, a lighter band under the progress.
struct XRayCoverageBand: View {
    @ObservedObject var xray: XRayController
    let duration: TimeInterval

    var body: some View {
        GeometryReader { geo in
            ForEach(Array(xray.coverage.enumerated()), id: \.offset) { _, range in
                if duration > 0, range.count == 2 {
                    let x = geo.size.width * CGFloat(range[0] / duration)
                    let w = geo.size.width * CGFloat((min(range[1], duration) - range[0]) / duration)
                    Rectangle()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: max(0, w), height: 4)
                        .offset(x: x)
                }
            }
        }
        .frame(height: 4)
        .allowsHitTesting(false)
    }
}
