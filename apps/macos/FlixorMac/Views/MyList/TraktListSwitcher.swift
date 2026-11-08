//
//  TraktListSwitcher.swift
//  FlixorMac
//
//  Chip row above the My List controls: the merged My List view, each of the
//  user's Trakt lists with its item count, and New List. Only shown when Trakt
//  is connected.
//

import SwiftUI
import FlixorKit

struct TraktListSwitcher: View {
    @ObservedObject var model: TraktListsViewModel
    let myListCount: Int
    let horizontalInset: CGFloat
    let onCreate: () -> Void
    let onEdit: (TraktUserList) -> Void
    let onDelete: (TraktUserList) -> Void

    @Environment(\.flixorTheme) private var theme

    private let maxChipTitleLength = 32

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.controlGap) {
                BrowseChip(title: String(localized: "My List"), count: myListCount, isSelected: model.selectedListId == nil) {
                    withAnimation(DS.Motion.quick) { model.select(nil) }
                }

                ForEach(model.lists) { list in
                    BrowseChip(
                        title: chipTitle(list.name),
                        count: model.count(for: list),
                        isSelected: model.selectedListId == list.id
                    ) {
                        withAnimation(DS.Motion.quick) { model.select(list.id) }
                    }
                    .help(list.name)
                    .contextMenu {
                        TraktListActions(list: list, onEdit: onEdit, onDelete: onDelete)
                    }
                }

                if model.isLoadingLists {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Loading Trakt lists")
                }

                if let error = model.listsError {
                    retryButton(error: error)
                }

                newListButton
            }
            .padding(.horizontal, horizontalInset)
            .padding(.vertical, DS.Space.s2)
        }
    }

    private func chipTitle(_ name: String) -> String {
        name.count > maxChipTitleLength ? String(name.prefix(maxChipTitleLength)) + "…" : name
    }

    private func retryButton(error: String) -> some View {
        Button {
            model.loadLists()
        } label: {
            Label("Couldn't load lists. Retry", systemImage: "exclamationmark.triangle.fill")
                .flixorFont(.callout, weight: .medium)
                .foregroundStyle(theme.warning)
        }
        .buttonStyle(.plain)
        .help(error)
        .accessibilityLabel("Couldn't load Trakt lists. Retry")
    }

    private var newListButton: some View {
        Button(action: onCreate) {
            Label("New List", systemImage: "plus")
                .flixorFont(.callout, weight: .semibold)
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal, DS.Space.s14)
                .padding(.vertical, DS.Space.s6)
                .background(Capsule().fill(theme.hoverFill))
                .overlay(Capsule().stroke(theme.separator, lineWidth: DS.Border.thin))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(model.isMutating)
        .accessibilityLabel("Create a new Trakt list")
    }
}

/// Edit and Delete, shared by the chip's context menu and the header's menu.
struct TraktListActions: View {
    let list: TraktUserList
    let onEdit: (TraktUserList) -> Void
    let onDelete: (TraktUserList) -> Void

    var body: some View {
        Button {
            onEdit(list)
        } label: {
            Label("Edit List…", systemImage: "pencil")
        }
        Button(role: .destructive) {
            onDelete(list)
        } label: {
            Label("Delete List…", systemImage: "trash")
        }
    }
}
