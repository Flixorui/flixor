//
//  MoodPicksRow.swift
//  FlixorMac
//
//  The Home "Tonight ✦" row: mood chips, and picks the AI chose from the
//  user's own Continue Watching and watchlist, each with a few words on why.
//  HomeView's lazy stack builds it only near the viewport.
//

import SwiftUI

/// Stable id of the Home mood picks row.
let homeMoodPicksRowId = "ai-mood-picks"

struct MoodPicksRow: View {
    let title: String
    let candidates: [MoodPickCandidate]
    let onTap: (MediaItem) -> Void

    @State private var mood: MoodPickMood = .lightShort
    @State private var picks: [MoodPick] = []
    @State private var isLoading = false
    @State private var error: String?
    @Environment(\.flixorTheme) private var theme

    private static let tint = Color(hex: 0xA78BFA)
    private static let cardWidth: CGFloat = 420

    private var taskKey: String { mood.rawValue + "|" + candidates.map(\.item.id).joined(separator: ",") }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s12) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s8) {
                Text(title).font(.flixor(.title2, weight: .bold)).foregroundStyle(theme.textPrimary)
                Image(systemName: "sparkles").font(.system(size: 14, weight: .semibold)).foregroundStyle(Self.tint)
                Text("From your watchlist and Continue Watching")
                    .font(.flixor(.footnote)).foregroundStyle(theme.textTertiary)
            }
            .padding(.horizontal, DS.Space.s20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s8) {
                    ForEach(MoodPickMood.allCases) { option in
                        Button { mood = option } label: {
                            Text(option.label)
                                .font(.flixor(.callout, weight: .semibold))
                                .foregroundStyle(option == mood ? Color.black : Color.white)
                                .padding(.horizontal, DS.Space.s14)
                                .padding(.vertical, DS.Space.s6)
                                .background(Capsule().fill(option == mood ? Color.white : Color.white.opacity(0.08)))
                                .overlay(Capsule().strokeBorder(Color.white.opacity(option == mood ? 0 : 0.12), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DS.Space.s20)
            }

            content
        }
        .task(id: taskKey) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && picks.isEmpty {
            SkeletonCarouselRow(itemWidth: Self.cardWidth, itemCount: 4, cardType: .landscape)
        } else if let error, picks.isEmpty {
            message(error)
        } else if picks.isEmpty {
            message(candidates.isEmpty
                    ? String(localized: "Add titles to your watchlist and they'll show up here by mood.")
                    : String(localized: "Nothing in your list fits this mood. Try another."))
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(picks) { pick in
                        VStack(alignment: .leading, spacing: DS.Space.s6) {
                            LandscapeCard(item: pick.item, width: Self.cardWidth) { onTap(pick.item) }
                            HStack(spacing: DS.Space.s6) {
                                Image(systemName: "sparkles").font(.system(size: 10, weight: .semibold)).foregroundStyle(Self.tint)
                                Text(pick.reason).font(.flixor(.footnote)).foregroundStyle(theme.textSecondary).lineLimit(1)
                            }
                            .frame(width: Self.cardWidth, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, DS.Space.s20)
                .padding(.vertical, DS.Space.s4)
            }
            .frame(height: Self.cardWidth * 0.5 + 40)
            .opacity(isLoading ? 0.5 : 1)
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.flixor(.callout))
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, DS.Space.s20)
            .frame(height: 80, alignment: .leading)
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let result = try await AIMoodPicksService.picks(mood: mood, candidates: candidates)
            guard !Task.isCancelled else { return }
            picks = result
        } catch {
            guard !Task.isCancelled else { return }
            picks = []
            self.error = error.localizedDescription
        }
    }
}
