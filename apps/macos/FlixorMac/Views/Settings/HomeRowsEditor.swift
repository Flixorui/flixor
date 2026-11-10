//
//  HomeRowsEditor.swift
//  FlixorMac
//
//  Reorder (drag), rename and hide every home row, plus "Reset to default
//  order". Embedded in Rows Settings. The list comes from HomeRowsStore, which
//  HomeViewModel fills as rows load.
//

import SwiftUI

struct HomeRowsEditor: View {
    @ObservedObject private var store = HomeRowsStore.shared
    @ObservedObject private var profileSettings = ProfileSettings.shared
    @Environment(\.flixorTheme) private var theme

    private static let rowHeight: CGFloat = 46
    private static let maxVisibleRows = 10

    var body: some View {
        let rows = store.orderedCatalog

        VStack(alignment: .leading, spacing: DS.Space.itemGap) {
            HStack {
                SettingsSectionHeader(title: "Rows")
                Spacer()
                Button("Reset Order") {
                    withAnimation(DS.Motion.standard) { store.resetOrder() }
                }
                .buttonStyle(.link)
                .font(.system(size: 11.5, weight: .medium))
                .padding(.bottom, -DS.Space.s8)
                .disabled(!store.hasCustomOrder)
                .accessibilityLabel(Text("Reset home rows to default order"))
            }

            SettingsGroupCard {
                if rows.isEmpty {
                    Text("Your rows appear here once the home screen has loaded.")
                        .flixorFont(.footnote)
                        .foregroundStyle(theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DS.Space.cardPadding)
                } else {
                    List {
                        ForEach(rows) { row in
                            HomeRowEditorRow(
                                row: row,
                                canMoveUp: row.id != rows.first?.id,
                                canMoveDown: row.id != rows.last?.id
                            )
                            .listRowInsets(EdgeInsets(top: 0, leading: DS.Space.s8, bottom: 0, trailing: DS.Space.s12))
                            .frame(height: Self.rowHeight)
                        }
                        .onMove { source, destination in
                            store.move(fromOffsets: source, toOffset: destination)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .frame(height: CGFloat(min(rows.count, Self.maxVisibleRows)) * (Self.rowHeight + 2) + DS.Space.s4)
                }
            }

            SettingsFootnote("Drag to reorder. Rows you turn off stay here so you can bring them back.")
        }
    }
}

private struct HomeRowEditorRow: View {
    let row: HomeRowDescriptor
    let canMoveUp: Bool
    let canMoveDown: Bool

    @ObservedObject private var store = HomeRowsStore.shared
    @ObservedObject private var profileSettings = ProfileSettings.shared
    @Environment(\.flixorTheme) private var theme
    @State private var isRenaming = false

    private var title: String { store.title(for: row.id, default: row.defaultTitle) }

    private var subtitle: String {
        var parts = [row.detail ?? row.kind.label]
        if store.customTitle(for: row.id) != nil {
            parts.append(String(localized: "Originally \"\(row.defaultTitle)\""))
        }
        return parts.joined(separator: " · ")
    }

    /// Continue Watching already has its own switch; both controls share it.
    private var isVisible: Binding<Bool> {
        if row.id == homeContinueWatchingRowId {
            return $profileSettings.showContinueWatching
        }
        return Binding(
            get: { !store.isHidden(row.id) },
            set: { store.setHidden(row.id, !$0) }
        )
    }

    var body: some View {
        HStack(spacing: DS.Space.s10) {
            Image(systemName: "line.3.horizontal")
                .font(.flixorIcon(DS.Icon.xs, weight: .medium))
                .foregroundStyle(theme.textTertiary)
                .accessibilityHidden(true)

            Image(systemName: row.kind.iconName)
                .font(.flixorIcon(DS.Icon.sm))
                .foregroundStyle(theme.textSecondary)
                .frame(width: DS.Icon.lg)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .flixorFont(.callout, weight: .medium)
                    .foregroundStyle(isVisible.wrappedValue ? theme.textPrimary : theme.textTertiary)
                    .lineLimit(1)
                Text(subtitle)
                    .flixorFont(.caption)
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: DS.Space.s8)

            Button {
                isRenaming = true
            } label: {
                Image(systemName: "pencil")
                    .font(.flixorIcon(DS.Icon.xs, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: DS.Icon.xl, height: DS.Icon.xl)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Rename")
            .accessibilityLabel(Text("Rename \(title)"))
            .popover(isPresented: $isRenaming, arrowEdge: .bottom) {
                HomeRowRenamePopover(row: row, isPresented: $isRenaming)
            }

            Toggle("", isOn: isVisible)
                .labelsHidden()
                .toggleStyle(.settingsSwitch)
                .controlSize(.mini)
                .accessibilityLabel(Text("Show \(title) on Home"))
        }
        .contextMenu {
            Button("Move Up") { store.move(row.id, by: -1) }
                .disabled(!canMoveUp)
            Button("Move Down") { store.move(row.id, by: 1) }
                .disabled(!canMoveDown)
            Divider()
            Button("Rename…") { isRenaming = true }
            if store.customTitle(for: row.id) != nil {
                Button("Use Default Name") {
                    store.rename(row.id, to: nil, defaultTitle: row.defaultTitle)
                }
            }
        }
        .accessibilityAction(named: Text("Move up")) {
            if canMoveUp { store.move(row.id, by: -1) }
        }
        .accessibilityAction(named: Text("Move down")) {
            if canMoveDown { store.move(row.id, by: 1) }
        }
    }
}

private struct HomeRowRenamePopover: View {
    let row: HomeRowDescriptor
    @Binding var isPresented: Bool

    @ObservedObject private var store = HomeRowsStore.shared
    @Environment(\.flixorTheme) private var theme
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.itemGap) {
            Text("Rename Row")
                .flixorFont(.callout, weight: .semibold)

            TextField(row.defaultTitle, text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit(save)
                .accessibilityLabel(Text("Row name"))

            HStack {
                Button("Use Default") {
                    store.rename(row.id, to: nil, defaultTitle: row.defaultTitle)
                    isPresented = false
                }
                .disabled(store.customTitle(for: row.id) == nil)

                Spacer()

                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DS.Space.cardPadding)
        .frame(width: 280)
        .onAppear {
            text = store.title(for: row.id, default: row.defaultTitle)
            isFocused = true
        }
    }

    private func save() {
        store.rename(row.id, to: text, defaultTitle: row.defaultTitle)
        isPresented = false
    }
}
