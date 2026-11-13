//
//  DetailsSectionOrderList.swift
//  FlixorMac
//
//  Settings list for the details-screen sections: drag (or use the arrows) to
//  reorder, toggle to show or hide, reset to defaults. The hero stays first.
//

import SwiftUI
import UniformTypeIdentifiers

struct DetailsSectionOrderList: View {
    @ObservedObject private var store = DetailsSectionsStore.shared
    @ObservedObject private var profileSettings = ProfileSettings.shared

    @State private var draggingKey: DetailsSectionKey?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.controlGap) {
            SettingsGroupCard {
                heroRow

                ForEach(Array(store.sections.enumerated()), id: \.element.key) { index, pref in
                    row(for: pref, index: index)
                        .onDrag {
                            draggingKey = pref.key
                            return NSItemProvider(object: pref.key.rawValue as NSString)
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: SectionDropDelegate(target: pref.key, dragging: $draggingKey, store: store)
                        )
                }
            }

            HStack {
                Text("Drag sections to reorder. In the tabbed layout each visible section becomes a tab.")
                    .font(.flixor(.caption))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset to Defaults") {
                    withAnimation(DS.Motion.standard) {
                        store.resetToDefaults()
                        profileSettings.showCastCrew = true
                        profileSettings.showRelatedContent = true
                    }
                }
                .controlSize(.small)
                .accessibilityLabel(Text("Reset details sections to defaults"))
            }
            .padding(.horizontal, DS.Space.s4)
        }
    }

    private var heroRow: some View {
        SettingsRow(
            icon: "photo.fill",
            iconColor: .gray,
            title: "Hero",
            subtitle: "Artwork, title, actions and overview. Always first."
        ) {
            Image(systemName: "lock.fill")
                .font(.flixorIcon(DS.Icon.xs))
                .foregroundStyle(.tertiary)
                .accessibilityLabel(Text("Hero position is fixed"))
        }
    }

    private func row(for pref: DetailsSectionPreference, index: Int) -> some View {
        let key = pref.key
        let isLast = index == store.sections.count - 1
        return HStack(spacing: 0) {
            Image(systemName: "line.3.horizontal")
                .font(.flixorIcon(DS.Icon.xs, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: DS.Space.s24)
                .padding(.leading, DS.Space.s8)
                .help("Drag to reorder")
                .accessibilityHidden(true)

            SettingsRow(
                icon: key.icon,
                iconColor: iconColor(for: key),
                title: .verbatim(key.title),
                subtitle: .verbatim(key.subtitle),
                showDivider: !isLast
            ) {
                HStack(spacing: DS.Space.s4) {
                    moveButton(key, offset: -1, systemImage: "chevron.up", label: "Move \(key.title) up")
                        .disabled(index == 0)
                    moveButton(key, offset: 1, systemImage: "chevron.down", label: "Move \(key.title) down")
                        .disabled(isLast)
                    Toggle("", isOn: enabledBinding(for: key))
                        .labelsHidden()
                        .accessibilityLabel(Text("Show \(key.title)"))
                        .padding(.leading, DS.Space.s8)
                }
            }
        }
        .contentShape(Rectangle())
    }

    private func moveButton(_ key: DetailsSectionKey, offset: Int, systemImage: String, label: String) -> some View {
        Button {
            withAnimation(DS.Motion.standard) { store.move(key, by: offset) }
        } label: {
            Image(systemName: systemImage)
                .font(.flixorIcon(DS.Icon.xs, weight: .semibold))
                .frame(width: DS.Space.s20, height: DS.Space.s20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(Text(label))
    }

    /// Cast and Suggested also drive the older profile toggles, which other
    /// code reads, so both stay in sync.
    private func enabledBinding(for key: DetailsSectionKey) -> Binding<Bool> {
        Binding(
            get: {
                let enabled = store.isEnabled(key)
                switch key {
                case .cast: return enabled && profileSettings.showCastCrew
                case .suggested: return enabled && profileSettings.showRelatedContent
                default: return enabled
                }
            },
            set: { value in
                store.setEnabled(key, value)
                switch key {
                case .cast: profileSettings.showCastCrew = value
                case .suggested: profileSettings.showRelatedContent = value
                default: break
                }
            }
        )
    }

    private func iconColor(for key: DetailsSectionKey) -> Color {
        switch key {
        case .episodes: return .blue
        case .suggested: return .teal
        case .collection: return .orange
        case .cast: return .purple
        case .trailers: return .red
        case .physical: return Color(hex: "0077B6")
        case .guidance: return .indigo
        case .comments: return .green
        case .about: return .gray
        }
    }
}

// MARK: - Drag & drop

private struct SectionDropDelegate: DropDelegate {
    let target: DetailsSectionKey
    @Binding var dragging: DetailsSectionKey?
    let store: DetailsSectionsStore

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        Task { @MainActor in
            withAnimation(DS.Motion.standard) {
                store.move(dragging, to: target)
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}
