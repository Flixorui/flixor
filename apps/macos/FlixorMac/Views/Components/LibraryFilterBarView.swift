//
//  LibraryFilterBarView.swift
//  FlixorMac
//
//  Filter / sort controls for the library experience.
//

import SwiftUI

struct LibraryFilterBarView: View {
    @ObservedObject var viewModel: LibraryViewModel
    var onSelectSection: (LibraryViewModel.LibrarySectionSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s18) {
            HStack(spacing: DS.Space.s16) {
                

                Spacer()

                viewModeToggle
            }

            HStack(alignment: .center, spacing: DS.Space.s16) {
                searchField

                if !viewModel.genres.isEmpty {
                    Picker("Genre", selection: genreSelection) {
                        Text("All Genres").tag("all")
                        ForEach(viewModel.genres) { option in
                            Text(option.label).tag(option.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 170)
                }

                if !viewModel.years.isEmpty {
                    Picker("Year", selection: yearSelection) {
                        Text("All Years").tag("all")
                        ForEach(viewModel.years) { option in
                            Text(option.label).tag(option.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 150)
                }

                Spacer()

                sortMenu
            }

            if !viewModel.sections.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Space.s10) {
                        ForEach(viewModel.sections) { section in
                            let isActive = viewModel.activeSection?.id == section.id
                            Button {
                                onSelectSection(section)
                            } label: {
                                Text(section.title)
                                    .font(.flixor(.callout, weight: .semibold))
                                    .padding(.horizontal, DS.Space.s14)
                                    .padding(.vertical, DS.Space.s8)
                                    .background(
                                        RoundedRectangle(cornerRadius: DS.Radius.r20, style: .continuous)
                                            .fill(isActive ? Color.white : Color.white.opacity(0.1))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DS.Radius.r20, style: .continuous)
                                            .stroke(Color.white.opacity(isActive ? 0 : 0.2), lineWidth: 1)
                                    )
                                    .foregroundStyle(isActive ? Color.black : Color.white.opacity(0.9))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, DS.Space.s2)
                }
            }
        }
        .padding(.horizontal, DS.Space.s64)
        .padding(.top, DS.Space.s24)
    }

    private var searchField: some View {
        HStack(spacing: DS.Space.s8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.6))
            TextField("Search library", text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
                .foregroundColor(.white)
        }
        .padding(.horizontal, DS.Space.s14)
        .padding(.vertical, DS.Space.s10)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.r10, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .frame(maxWidth: 260)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(LibraryViewModel.SortOption.allCases) { option in
                Button {
                    viewModel.sort = option
                } label: {
                    if viewModel.sort == option {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            HStack(spacing: DS.Space.s6) {
                Image(systemName: "arrow.up.arrow.down.circle")
                Text(viewModel.sort.label)
                    .font(.flixor(.callout, weight: .semibold))
            }
            .padding(.horizontal, DS.Space.s14)
            .padding(.vertical, DS.Space.s10)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r10, style: .continuous))
        }
        .menuStyle(.borderlessButton)
    }

    private var viewModeToggle: some View {
        HStack(spacing: DS.Space.s8) {
            toggleButton(
                systemImage: "square.grid.2x2",
                isActive: viewModel.viewMode == .grid
            ) {
                viewModel.viewMode = .grid
            }

            toggleButton(
                systemImage: "list.bullet",
                isActive: viewModel.viewMode == .list
            ) {
                viewModel.viewMode = .list
            }
        }
    }

    private func toggleButton(systemImage: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.flixorIcon(DS.Icon.sm, weight: .semibold))
                .foregroundStyle(isActive ? Color.black : Color.white.opacity(0.85))
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.r8, style: .continuous)
                        .fill(isActive ? Color.white : Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.r8, style: .continuous)
                        .stroke(Color.white.opacity(isActive ? 0 : 0.2), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var genreSelection: Binding<String> {
        Binding<String>(
            get: { viewModel.selectedGenre?.id ?? "all" },
            set: { newValue in
                if newValue == "all" {
                    viewModel.updateGenre(nil)
                } else if let selected = viewModel.genres.first(where: { $0.id == newValue }) {
                    viewModel.updateGenre(selected)
                }
            }
        )
    }

    private var yearSelection: Binding<String> {
        Binding<String>(
            get: { viewModel.selectedYear?.id ?? "all" },
            set: { newValue in
                if newValue == "all" {
                    viewModel.updateYear(nil)
                } else if let selected = viewModel.years.first(where: { $0.id == newValue }) {
                    viewModel.updateYear(selected)
                }
            }
        )
    }
}
