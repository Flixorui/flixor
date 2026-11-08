//
//  CollectionSourceEditorView.swift
//  FlixorMac
//
//  Sheet that adds or edits one source of a collection, with a preview of what
//  the source returns before it is saved.
//

import SwiftUI
import FlixorKit

struct CollectionSourceEditorView: View {
    let existing: UserCollectionSource?
    let onSave: (UserCollectionSource) -> Void

    @StateObject private var model: CollectionSourceEditorModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.flixorTheme) private var theme

    init(
        template: UserCollectionSource.Template,
        existing: UserCollectionSource?,
        onSave: @escaping (UserCollectionSource) -> Void
    ) {
        self.existing = existing
        self.onSave = onSave
        _model = StateObject(wrappedValue: CollectionSourceEditorModel(template: template, existing: existing))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s20) {
                    form
                    previewSection
                }
                .padding(DS.Space.sheetPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .frame(width: 600, height: 620)
        .background(theme.surface)
        .task {
            await model.loadAddonCatalogs()
            await model.loadGenres()
        }
        .onChange(of: model.draftKind) { _ in model.resetPreview() }
    }

    private var header: some View {
        HStack(spacing: DS.Space.s12) {
            Image(systemName: model.template.iconName)
                .font(.flixorIcon(DS.Icon.md))
                .foregroundStyle(theme.accent)
            Text(existing == nil ? "Add \(model.template.title)" : "Edit \(model.template.title)")
                .flixorFont(.headline)
                .foregroundStyle(theme.textPrimary)
            Spacer()
        }
        .padding(DS.Space.sheetPadding)
    }

    private var footer: some View {
        HStack(spacing: DS.Space.s12) {
            Button("Preview") { model.runPreview() }
                .disabled(model.draftSource == nil)
                .accessibilityLabel("Preview this source")
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(existing == nil ? "Add Source" : "Save") {
                if let source = model.draftSource {
                    onSave(source)
                    dismiss()
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(model.draftSource == nil)
        }
        .padding(DS.Space.sheetPadding)
    }

    // MARK: - Forms

    @ViewBuilder
    private var form: some View {
        switch model.template {
        case .addonCatalog: addonForm
        case .tmdbDiscover: discoverForm
        case .tmdbCollection: collectionForm
        case .person: personForm
        case .traktList: traktForm
        }
    }

    // MARK: Addon

    @ViewBuilder
    private var addonForm: some View {
        if model.isLoadingAddons {
            loadingRow("Loading addon catalogs")
        } else if model.addonCatalogs.isEmpty {
            BrowseMessageView(
                systemImage: "puzzlepiece.extension",
                title: "No addon catalogs",
                message: "Install a Stremio addon that offers catalogs, then come back."
            )
        } else {
            TextField("Filter catalogs", text: $model.addonFilter)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Filter catalogs")
            VStack(spacing: DS.Space.s4) {
                ForEach(model.filteredAddonCatalogs) { entry in
                    CollectionPickRow(
                        title: entry.catalog.displayName,
                        subtitle: entry.addonName,
                        imageURL: nil,
                        placeholderIcon: "puzzlepiece.extension.fill",
                        isSelected: model.isSelected(entry)
                    ) { model.select(entry) }
                }
            }
        }
    }

    // MARK: Discover

    private var discoverForm: some View {
        VStack(alignment: .leading, spacing: DS.Space.s20) {
            field("Type") {
                BrowseChipBar(
                    options: TMDBDiscoverMediaType.allCases,
                    selection: Binding(
                        get: { model.discover.mediaType },
                        set: { model.setMediaType($0) }
                    ),
                    title: { $0 == .movie ? "Movies" : "TV Shows" }
                )
            }

            if !model.genres.isEmpty {
                field("Genres") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: DS.Space.controlGap)],
                              alignment: .leading, spacing: DS.Space.controlGap) {
                        ForEach(model.genres, id: \.id) { genre in
                            BrowseChip(
                                title: genre.name,
                                isSelected: model.discover.genreIds.contains(genre.id)
                            ) { model.toggleGenre(genre) }
                        }
                    }
                }
            }

            field("Production company") { companyPicker }

            if model.discover.mediaType == .tv {
                field("Network") {
                    Picker("Network", selection: Binding(
                        get: { model.discover.networkId },
                        set: { model.setNetwork(id: $0) }
                    )) {
                        Text("Any").tag(Int?.none)
                        ForEach(CollectionSourceEditorModel.networks, id: \.id) { network in
                            Text(network.name).tag(Int?.some(network.id))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                    .accessibilityLabel("Network")
                }
            }

            HStack(alignment: .top, spacing: DS.Space.s20) {
                field("Year range") {
                    HStack(spacing: DS.Space.controlGap) {
                        TextField("From", text: $model.yearFromText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .accessibilityLabel("From year")
                        Text("to")
                            .flixorFont(.callout)
                            .foregroundStyle(theme.textSecondary)
                        TextField("To", text: $model.yearToText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .accessibilityLabel("To year")
                    }
                }
                field("Sort by") {
                    Picker("Sort by", selection: $model.discover.sort) {
                        ForEach(TMDBDiscoverSort.allCases, id: \.self) { sort in
                            Text(sort.collectionTitle).tag(sort)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                    .accessibilityLabel("Sort by")
                }
            }
        }
    }

    @ViewBuilder
    private var companyPicker: some View {
        if let name = model.discover.companyName {
            selectedRow(title: name, subtitle: "Production company", accessibilityTarget: "company") {
                model.clearCompany()
            }
        } else {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                TextField("Search companies (optional)", text: $model.companyText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search production companies")
                    .onChange(of: model.companyText) { _ in model.companyTextChanged() }
                if model.isSearchingCompanies {
                    loadingRow("Searching")
                }
                ForEach(model.companyResults) { company in
                    CollectionPickRow(
                        title: company.name,
                        subtitle: company.originCountry,
                        imageURL: TMDBImageURL.url(company.logoPath, size: .w185),
                        placeholderIcon: "building.2.fill",
                        isSelected: false
                    ) { model.selectCompany(company) }
                }
            }
        }
    }

    // MARK: Movie collection

    @ViewBuilder
    private var collectionForm: some View {
        if let selected = model.selectedCollection {
            selectedRow(
                title: selected.name,
                subtitle: "TMDB movie collection",
                imageURL: TMDBImageURL.url(selected.posterPath, size: .w185),
                accessibilityTarget: "collection"
            ) { model.selectedCollection = nil }
        } else {
            searchField(prompt: "Search movie collections, like Alien")
            searchStatus(isEmpty: model.collectionResults.isEmpty)
            ForEach(model.collectionResults) { result in
                CollectionPickRow(
                    title: result.name,
                    subtitle: result.overview,
                    imageURL: TMDBImageURL.url(result.posterPath, size: .w185),
                    placeholderIcon: "film.stack.fill",
                    isSelected: false
                ) { model.select(result) }
            }
        }
    }

    // MARK: Person

    @ViewBuilder
    private var personForm: some View {
        if let person = model.selectedPerson {
            selectedRow(
                title: person.name,
                subtitle: "Person",
                imageURL: TMDBImageURL.url(person.profilePath, size: .w185),
                accessibilityTarget: "person"
            ) { model.selectedPerson = nil }

            HStack(alignment: .top, spacing: DS.Space.s20) {
                field("Credits") {
                    Picker("Credits", selection: personBinding(person, \.credits)) {
                        ForEach(UserCollectionSource.Person.Credits.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                    .accessibilityLabel("Credits")
                }
                field("Order") {
                    Picker("Order", selection: personBinding(person, \.order)) {
                        ForEach(UserCollectionSource.Person.Order.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                    .accessibilityLabel("Order")
                }
            }
        } else {
            searchField(prompt: "Search people by name")
            searchStatus(isEmpty: model.peopleResults.isEmpty)
            ForEach(model.peopleResults) { person in
                CollectionPickRow(
                    title: person.name,
                    subtitle: person.knownForDepartment,
                    imageURL: TMDBImageURL.url(person.profilePath, size: .w185),
                    placeholderIcon: "person.fill",
                    isSelected: false
                ) { model.select(person) }
            }
        }
    }

    /// `person` is the fallback for reads while the selection is being cleared.
    private func personBinding<Value>(
        _ person: UserCollectionSource.Person,
        _ keyPath: WritableKeyPath<UserCollectionSource.Person, Value>
    ) -> Binding<Value> {
        Binding(
            get: { (model.selectedPerson ?? person)[keyPath: keyPath] },
            set: { model.selectedPerson?[keyPath: keyPath] = $0 }
        )
    }

    // MARK: Trakt

    @ViewBuilder
    private var traktForm: some View {
        if let list = model.selectedTraktList {
            selectedRow(
                title: list.name,
                subtitle: list.owner.map { "Trakt list by \($0)" } ?? "Trakt list",
                accessibilityTarget: "list"
            ) { model.selectedTraktList = nil }
        } else {
            searchField(prompt: "Paste a trakt.tv list URL, or search by name")
            searchStatus(isEmpty: model.traktResults.isEmpty)
            ForEach(model.traktResults) { list in
                CollectionPickRow(
                    title: list.name,
                    subtitle: traktSubtitle(list),
                    imageURL: nil,
                    placeholderIcon: "list.star",
                    isSelected: false
                ) { model.select(list) }
            }
        }
    }

    private func traktSubtitle(_ list: TraktPublicList) -> String {
        var parts: [String] = []
        if let owner = list.user?.username ?? list.user?.name { parts.append("by \(owner)") }
        if let count = list.itemCount { parts.append("\(count) \(count == 1 ? "item" : "items")") }
        if let likes = list.likes, likes > 0 { parts.append("\(likes) \(likes == 1 ? "like" : "likes")") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Shared pieces

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.controlGap) {
            Text(title)
                .flixorFont(.footnote, weight: .semibold)
                .foregroundStyle(theme.textSecondary)
            content()
        }
    }

    private func searchField(prompt: String) -> some View {
        TextField(prompt, text: $model.searchText)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel(prompt)
            .onChange(of: model.searchText) { _ in model.searchTextChanged() }
    }

    @ViewBuilder
    private func searchStatus(isEmpty: Bool) -> some View {
        if model.isSearching {
            loadingRow("Searching")
        } else if let error = model.searchError {
            Text(error)
                .flixorFont(.callout)
                .foregroundStyle(theme.danger)
        } else if model.hasSearched && isEmpty {
            Text("No results.")
                .flixorFont(.callout)
                .foregroundStyle(theme.textSecondary)
        }
    }

    private func loadingRow(_ label: String) -> some View {
        HStack(spacing: DS.Space.controlGap) {
            ProgressView().controlSize(.small)
            Text(label)
                .flixorFont(.callout)
                .foregroundStyle(theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func selectedRow(
        title: String,
        subtitle: String?,
        imageURL: URL? = nil,
        accessibilityTarget: String,
        onClear: @escaping () -> Void
    ) -> some View {
        HStack(spacing: DS.Space.s12) {
            CollectionPickThumbnail(url: imageURL, placeholderIcon: model.template.iconName)
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text(title)
                    .flixorFont(.callout, weight: .semibold)
                    .foregroundStyle(theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .flixorFont(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            Spacer()
            Button("Change", action: onClear)
                .accessibilityLabel("Change \(accessibilityTarget)")
        }
        .padding(DS.Space.s12)
        .background(theme.hoverFill, in: RoundedRectangle(cornerRadius: DS.Radius.compactCard, style: .continuous))
    }

    // MARK: - Preview

    @ViewBuilder
    private var previewSection: some View {
        switch model.preview {
        case .idle:
            EmptyView()
        case .loading:
            loadingRow("Loading preview")
        case .empty:
            Text("This source returned no titles.")
                .flixorFont(.callout)
                .foregroundStyle(theme.textSecondary)
        case .failed(let message):
            Text(message)
                .flixorFont(.callout)
                .foregroundStyle(theme.danger)
        case .loaded(let items, let hasMore):
            VStack(alignment: .leading, spacing: DS.Space.controlGap) {
                Text(hasMore ? "Preview (first \(items.count) titles, more available)" : "Preview (\(items.count) titles)")
                    .flixorFont(.footnote, weight: .semibold)
                    .foregroundStyle(theme.textSecondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Space.s12) {
                        ForEach(items) { item in
                            CachedAsyncImage(url: item.thumb.flatMap(URL.init(string:)))
                                .frame(width: 92, height: 138)
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.thumbnail, style: .continuous))
                                .accessibilityLabel(item.title)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Pick row

struct CollectionPickThumbnail: View {
    let url: URL?
    let placeholderIcon: String

    @Environment(\.flixorTheme) private var theme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                .fill(theme.surfaceElevated)
            if let url {
                CachedAsyncImage(url: url, contentMode: .fill) { Color.clear }
            } else {
                Image(systemName: placeholderIcon)
                    .font(.flixorIcon(DS.Icon.sm))
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .frame(width: 36, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct CollectionPickRow: View {
    let title: String
    let subtitle: String?
    let imageURL: URL?
    let placeholderIcon: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.flixorTheme) private var theme
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s12) {
                CollectionPickThumbnail(url: imageURL, placeholderIcon: placeholderIcon)
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    Text(title)
                        .flixorFont(.callout, weight: .medium)
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .flixorFont(.caption)
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: DS.Space.s8)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.accent)
                }
            }
            .padding(DS.Space.s8)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                    .fill(isHovered || isSelected ? theme.hoverFill : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(subtitle.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
