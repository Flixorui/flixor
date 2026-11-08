//
//  CollectionCoverPicker.swift
//  FlixorMac
//
//  Sheet that picks a collection's cover from its own titles.
//

import SwiftUI

struct CollectionCoverPicker: View {
    let collection: UserCollection
    let onPick: (UserCollectionCover) -> Void

    @State private var style: UserCollectionCover.Style = .backdrop
    @State private var preview: UserCollectionPreview?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.flixorTheme) private var theme

    private func imageURL(for item: MediaItem) -> String? {
        let value = style == .poster ? item.thumb : item.art
        return value?.isEmpty == false ? value : nil
    }

    private var candidates: [MediaItem] {
        preview?.items.filter { imageURL(for: $0) != nil } ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Choose Cover")
                    .flixorFont(.headline)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                BrowseChipBar(
                    options: UserCollectionCover.Style.allCases,
                    selection: $style,
                    title: { $0.title }
                )
            }
            .padding(DS.Space.sheetPadding)
            Divider()
            content
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(DS.Space.sheetPadding)
        }
        .frame(width: 620, height: 560)
        .background(theme.surface)
        .task {
            preview = await UserCollectionPreviewCache.shared.preview(for: collection)
        }
    }

    @ViewBuilder
    private var content: some View {
        if preview == nil {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading titles")
        } else if candidates.isEmpty {
            BrowseMessageView(
                systemImage: "photo",
                title: "No artwork found",
                message: preview?.failures.first?.message ?? "None of the first titles have this kind of artwork."
            )
            .frame(maxHeight: .infinity)
        } else {
            let minimum: CGFloat = style == .poster ? 100 : 180
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum), spacing: DS.Space.s12)], spacing: DS.Space.s12) {
                    ForEach(candidates) { item in
                        Button {
                            if let url = imageURL(for: item) {
                                onPick(UserCollectionCover(url: url, style: style))
                            }
                            dismiss()
                        } label: {
                            CachedAsyncImage(url: imageURL(for: item).flatMap(URL.init(string:)))
                                .aspectRatio(style == .poster ? 2.0 / 3.0 : 16.0 / 9.0, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.thumbnail, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Use artwork from \(item.title)")
                    }
                }
                .padding(DS.Space.sheetPadding)
            }
        }
    }
}
