//
//  UserCollectionEditorView.swift
//  FlixorMac
//
//  Sheet that creates or edits a collection: name, cover, home row toggle and
//  its sources (add, edit, reorder, remove).
//

import SwiftUI

/// Presents the editor; a nil collection means "create new".
struct UserCollectionEditorRequest: Identifiable {
    let id = UUID()
    let collection: UserCollection?
}

struct UserCollectionEditorView: View {
    let isNew: Bool
    var onDeleted: (() -> Void)?

    @State private var draft: UserCollection
    @State private var sourceRequest: SourceRequest?
    @State private var showCoverPicker = false
    @State private var confirmDelete = false

    @ObservedObject private var store = UserCollectionsStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.flixorTheme) private var theme

    private struct SourceRequest: Identifiable {
        let id = UUID()
        let template: UserCollectionSource.Template
        let existing: UserCollectionSource?
    }

    init(collection: UserCollection?, onDeleted: (() -> Void)? = nil) {
        isNew = collection == nil
        self.onDeleted = onDeleted
        _draft = State(initialValue: collection ?? .new())
    }

    private var trimmedName: String {
        draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && !draft.sources.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(isNew ? "New Collection" : "Edit Collection")
                .flixorFont(.headline)
                .foregroundStyle(theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Space.sheetPadding)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s20) {
                    detailsSection
                    sourcesSection
                }
                .padding(DS.Space.sheetPadding)
            }
            Divider()
            footer
        }
        .frame(width: 620, height: 640)
        .background(theme.surface)
        .sheet(item: $sourceRequest) { request in
            CollectionSourceEditorView(template: request.template, existing: request.existing) { source in
                apply(source)
            }
        }
        .sheet(isPresented: $showCoverPicker) {
            CollectionCoverPicker(collection: draft) { draft.cover = $0 }
        }
        .confirmationDialog(
            "Delete \(draft.name)?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Collection", role: .destructive) {
                store.delete(id: draft.id)
                dismiss()
                onDeleted?()
            }
        } message: {
            Text("This removes the collection and its home row. Titles and sources aren't affected.")
        }
    }

    private var footer: some View {
        HStack(spacing: DS.Space.s12) {
            if !isNew {
                Button("Delete", role: .destructive) { confirmDelete = true }
                    .accessibilityLabel("Delete collection")
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(isNew ? "Create" : "Save") {
                draft.name = trimmedName
                store.save(draft)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)
        }
        .padding(DS.Space.sheetPadding)
    }

    // MARK: - Details

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            VStack(alignment: .leading, spacing: DS.Space.controlGap) {
                sectionLabel("Name")
                TextField("Collection name", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Collection name")
            }

            HStack(spacing: DS.Space.s12) {
                coverThumbnail
                VStack(alignment: .leading, spacing: DS.Space.s4) {
                    sectionLabel("Cover")
                    Text(draft.cover == nil ? "Optional. Pick a poster or backdrop from this collection." : "Picked from this collection.")
                        .flixorFont(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer()
                if draft.cover != nil {
                    Button("Remove") { draft.cover = nil }
                        .accessibilityLabel("Remove cover")
                }
                Button("Choose") { showCoverPicker = true }
                    .disabled(draft.sources.isEmpty)
                    .accessibilityLabel("Choose cover")
            }

            Toggle("Show as a row on Home", isOn: $draft.showOnHome)
                .toggleStyle(.switch)
                .flixorFont(.callout)
                .foregroundStyle(theme.textPrimary)
                .accessibilityLabel("Show as a row on Home")
        }
    }

    private var coverThumbnail: some View {
        CollectionPickThumbnail(
            url: draft.cover.flatMap { URL(string: $0.url) },
            placeholderIcon: "photo"
        )
    }

    // MARK: - Sources

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.controlGap) {
            HStack {
                sectionLabel("Sources")
                Spacer()
                Menu {
                    ForEach(UserCollectionSource.Template.allCases) { template in
                        Button {
                            sourceRequest = SourceRequest(template: template, existing: nil)
                        } label: {
                            Label(template.title, systemImage: template.iconName)
                        }
                    }
                } label: {
                    Label("Add Source", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Add source")
            }

            if draft.sources.isEmpty {
                Text("Add at least one source: an addon catalog, a TMDB query, a movie collection, a person or a Trakt list.")
                    .flixorFont(.callout)
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DS.Space.s16)
                    .background(theme.hoverFill, in: RoundedRectangle(cornerRadius: DS.Radius.compactCard, style: .continuous))
            } else {
                SettingsGroupCard {
                    ForEach(Array(draft.sources.enumerated()), id: \.element.id) { index, source in
                        SettingsRow(
                            icon: source.template.iconName,
                            iconColor: .blue,
                            title: source.title,
                            subtitle: source.subtitle,
                            showDivider: index < draft.sources.count - 1
                        ) {
                            sourceActions(index: index, source: source)
                        }
                    }
                }
            }
        }
    }

    private func sourceActions(index: Int, source: UserCollectionSource) -> some View {
        HStack(spacing: DS.Space.s4) {
            iconButton("chevron.up", label: "Move \(source.title) up", disabled: index == 0) {
                draft.sources.swapAt(index, index - 1)
            }
            iconButton("chevron.down", label: "Move \(source.title) down", disabled: index == draft.sources.count - 1) {
                draft.sources.swapAt(index, index + 1)
            }
            iconButton("pencil", label: "Edit \(source.title)", disabled: false) {
                sourceRequest = SourceRequest(template: source.template, existing: source)
            }
            iconButton("trash", label: "Remove \(source.title)", disabled: false) {
                draft.sources.remove(at: index)
            }
        }
    }

    private func iconButton(_ name: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.flixorIcon(DS.Icon.xs))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? theme.textTertiary : theme.textSecondary)
        .disabled(disabled)
        .accessibilityLabel(label)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .flixorFont(.footnote, weight: .semibold)
            .foregroundStyle(theme.textSecondary)
    }

    private func apply(_ source: UserCollectionSource) {
        if let index = draft.sources.firstIndex(where: { $0.id == source.id }) {
            draft.sources[index] = source
        } else {
            draft.sources.append(source)
        }
        if trimmedName.isEmpty {
            draft.name = source.title
        }
    }
}
