//
//  DetailsCommentsSection.swift
//  FlixorMac
//
//  Trakt comments for the title on screen (works without a Trakt login):
//  author, rating, likes, date and review badge; spoilers stay blurred until
//  clicked; sort by likes or newest; "Show more" paging.
//

import SwiftUI
import FlixorKit

// MARK: - Model

@MainActor
final class DetailsCommentsModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    enum Sort: String, CaseIterable, Identifiable {
        case likes
        case newest

        var id: String { rawValue }
        var label: String { self == .likes ? String(localized: "Most Liked") : String(localized: "Newest") }
        var traktSort: TraktCommentSort { self == .likes ? .likes : .newest }
    }

    @Published private(set) var comments: [TraktComment] = []
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = false
    @Published private(set) var totalCount = 0
    @Published private(set) var loadMoreError: String?
    @Published private(set) var sort: Sort = .likes
    @Published var revealedSpoilers: Set<Int> = []
    @Published var expanded: Set<Int> = []

    private var target: WatchStateTarget?
    private var resolvedTarget: WatchStateTarget?
    private var page = 1
    /// Bumped on every reset so late responses for an old title/sort are dropped.
    private var generation = 0
    private let pageSize = 10

    /// Loads the first page for `target` unless it's already loaded or loading.
    func load(target: WatchStateTarget?) async {
        if target == self.target, phase != .idle, !isFailed { return }
        reset(for: target)
        guard target != nil else { return }
        await fetchFirstPage()
    }

    func setSort(_ newSort: Sort) async {
        guard newSort != sort else { return }
        sort = newSort
        let current = target
        reset(for: current)
        guard current != nil else { return }
        await fetchFirstPage()
    }

    func retry() async {
        let current = target
        reset(for: current)
        guard current != nil else { return }
        await fetchFirstPage()
    }

    func loadMore() async {
        guard hasMore, !isLoadingMore, phase == .loaded, let resolved = resolvedTarget else { return }
        let gen = generation
        isLoadingMore = true
        loadMoreError = nil
        do {
            let result = try await TraktCommentsService.shared.comments(
                for: resolved, sort: sort.traktSort, page: page + 1, limit: pageSize
            )
            guard gen == generation else { return }
            let known = Set(comments.map(\.id))
            comments.append(contentsOf: result.items.filter { !known.contains($0.id) })
            page = result.page
            hasMore = result.hasMore
            totalCount = max(totalCount, result.itemCount)
        } catch {
            guard gen == generation else { return }
            if !Self.isCancellation(error) { loadMoreError = Self.message(for: error) }
        }
        isLoadingMore = false
    }

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    private func reset(for target: WatchStateTarget?) {
        generation += 1
        self.target = target
        resolvedTarget = nil
        comments = []
        page = 1
        hasMore = false
        totalCount = 0
        isLoadingMore = false
        loadMoreError = nil
        revealedSpoilers = []
        expanded = []
        phase = .idle
    }

    private func fetchFirstPage() async {
        guard let target else { return }
        let gen = generation
        phase = .loading
        let resolved = await WatchStateService.shared.resolve(target, needTitleIds: true)
        guard gen == generation else { return }
        guard !Task.isCancelled else {
            phase = .idle
            return
        }
        resolvedTarget = resolved
        do {
            let result = try await TraktCommentsService.shared.comments(
                for: resolved, sort: sort.traktSort, page: 1, limit: pageSize
            )
            guard gen == generation else { return }
            comments = result.items
            page = result.page
            hasMore = result.hasMore
            totalCount = result.itemCount
            phase = .loaded
        } catch {
            guard gen == generation else { return }
            // A cancelled load (section scrolled/tabbed away) retries on the next appearance.
            phase = Self.isCancellation(error) ? .idle : .failed(Self.message(for: error))
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }

    private static func message(for error: Error) -> String {
        if error is TraktCommentsService.CommentsError {
            return String(localized: "This title couldn't be found on Trakt.")
        }
        if let urlError = error as? URLError, urlError.code == .notConnectedToInternet {
            return String(localized: "You're offline.")
        }
        return String(localized: "Couldn't load comments from Trakt.")
    }
}

// MARK: - Section

struct DetailsCommentsSection: View {
    @ObservedObject var model: DetailsCommentsModel
    let target: WatchStateTarget?

    @Environment(\.flixorTheme) private var theme

    private let columns = [GridItem(.adaptive(minimum: 380), spacing: DS.Space.s16, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            header

            switch model.phase {
            case .idle, .loading:
                HStack(spacing: DS.Space.controlGap) {
                    ProgressView().controlSize(.small)
                    Text("Loading comments…")
                        .flixorFont(.callout)
                        .foregroundStyle(theme.textSecondary)
                }
                .padding(.vertical, DS.Space.s24)
            case .failed(let message):
                stateMessage(icon: "exclamationmark.bubble", title: message, actionTitle: String(localized: "Try Again")) {
                    Task { await model.retry() }
                }
            case .loaded:
                if model.comments.isEmpty {
                    stateMessage(icon: "text.bubble", title: String(localized: "No comments on Trakt yet."), actionTitle: nil, action: nil)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: DS.Space.s16) {
                        ForEach(model.comments) { comment in
                            TraktCommentCard(
                                comment: comment,
                                isSpoilerRevealed: model.revealedSpoilers.contains(comment.id),
                                isExpanded: model.expanded.contains(comment.id),
                                onRevealSpoiler: { model.revealedSpoilers.insert(comment.id) },
                                onToggleExpanded: {
                                    if model.expanded.contains(comment.id) {
                                        model.expanded.remove(comment.id)
                                    } else {
                                        model.expanded.insert(comment.id)
                                    }
                                }
                            )
                        }
                    }
                    footer
                }
            }
        }
        .task(id: target) {
            await model.load(target: target)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.controlGap) {
            Text("Comments")
                .flixorFont(.title2)
                .foregroundStyle(theme.textPrimary)
            if model.totalCount > 0 {
                Text("\(model.totalCount)")
                    .flixorFont(.callout)
                    .foregroundStyle(theme.textTertiary)
            }
            Text("from Trakt")
                .flixorFont(.caption)
                .foregroundStyle(theme.textTertiary)

            Spacer(minLength: DS.Space.itemGap)

            Picker("Sort comments", selection: Binding(
                get: { model.sort },
                set: { newValue in Task { await model.setSort(newValue) } }
            )) {
                ForEach(DetailsCommentsModel.Sort.allCases) { sort in
                    Text(sort.label).tag(sort)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .disabled(model.phase == .loading)
            .accessibilityLabel(Text("Sort comments"))
        }
    }

    @ViewBuilder private var footer: some View {
        if model.hasMore || model.loadMoreError != nil {
            HStack(spacing: DS.Space.itemGap) {
                Button {
                    Task { await model.loadMore() }
                } label: {
                    HStack(spacing: DS.Space.controlGap) {
                        if model.isLoadingMore {
                            ProgressView().controlSize(.small)
                        }
                        Text(model.loadMoreError == nil ? "Show More" : "Retry")
                            .flixorFont(.callout, weight: .semibold)
                    }
                    .foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, DS.Space.s16)
                    .padding(.vertical, DS.Space.s8)
                    .background(Capsule(style: .continuous).fill(theme.hoverFill))
                    .overlay(Capsule(style: .continuous).strokeBorder(theme.separatorStrong, lineWidth: DS.Border.thin))
                }
                .buttonStyle(.plain)
                .disabled(model.isLoadingMore)
                .accessibilityLabel(Text("Show more comments"))

                if let error = model.loadMoreError {
                    Text(error)
                        .flixorFont(.footnote)
                        .foregroundStyle(theme.danger)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func stateMessage(icon: String, title: String, actionTitle: String?, action: (() -> Void)?) -> some View {
        HStack(spacing: DS.Space.itemGap) {
            Image(systemName: icon)
                .font(.flixorIcon(DS.Icon.lg))
                .foregroundStyle(theme.textTertiary)
            Text(title)
                .flixorFont(.callout)
                .foregroundStyle(theme.textSecondary)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.small)
                    .accessibilityLabel(Text(actionTitle))
            }
        }
        .padding(DS.Space.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(theme.surfaceOverlay)
        )
    }
}

// MARK: - Comment Card

private struct TraktCommentCard: View {
    let comment: TraktComment
    let isSpoilerRevealed: Bool
    let isExpanded: Bool
    let onRevealSpoiler: () -> Void
    let onToggleExpanded: () -> Void

    @Environment(\.flixorTheme) private var theme

    private var authorName: String {
        if let name = comment.user?.name, !name.isEmpty { return name }
        return comment.user?.username ?? String(localized: "Trakt user")
    }

    /// Whole comment flagged as spoiler, or inline [spoiler] tags in the text.
    private var hasSpoiler: Bool {
        comment.spoiler || comment.comment.range(of: "[spoiler]", options: .caseInsensitive) != nil
    }

    private var isHidden: Bool { hasSpoiler && !isSpoilerRevealed }

    private var displayText: String {
        comment.comment
            .replacingOccurrences(of: "[spoiler]", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "[/spoiler]", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isLong: Bool { displayText.count > 360 }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.itemGap) {
            header
            badges
            commentBody
            footer
        }
        .padding(DS.Space.cardPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(theme.surfaceOverlay)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(theme.separator, lineWidth: DS.Border.thin)
        )
    }

    private var header: some View {
        HStack(spacing: DS.Space.s10) {
            avatar
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text(authorName)
                    .flixorFont(.callout, weight: .semibold)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                if let username = comment.user?.username, !username.isEmpty, username != authorName {
                    Text("@\(username)")
                        .flixorFont(.caption)
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: DS.Space.controlGap)
            if let date = TraktCommentDate.parse(comment.createdAt) {
                Text(TraktCommentDate.relative(date))
                    .flixorFont(.caption)
                    .foregroundStyle(theme.textTertiary)
                    .help(TraktCommentDate.full(date))
            }
        }
    }

    private var avatar: some View {
        Group {
            if let avatar = comment.user?.avatarURL, let url = URL(string: avatar) {
                CachedAsyncImage(url: url, aspectRatio: 1, contentMode: .fill)
            } else {
                ZStack {
                    theme.surfaceElevated
                    Text(String(authorName.prefix(1)).uppercased())
                        .flixorFont(.callout, weight: .semibold)
                        .foregroundStyle(theme.textSecondary)
                }
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    @ViewBuilder private var badges: some View {
        if comment.review || hasSpoiler || comment.userRating != nil {
            HStack(spacing: DS.Space.s6) {
                if let rating = comment.userRating {
                    badge(text: "\(rating)/10", icon: "star.fill", tint: theme.warning)
                        .accessibilityLabel(Text("Rated \(rating) out of 10"))
                }
                if comment.review {
                    badge(text: String(localized: "REVIEW"), icon: "doc.text.fill", tint: theme.accent)
                }
                if hasSpoiler {
                    badge(text: String(localized: "SPOILER"), icon: "exclamationmark.triangle.fill", tint: theme.danger)
                }
            }
        }
    }

    private func badge(text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: DS.Space.s4) {
            Image(systemName: icon)
                .font(.flixorIcon(DS.Icon.xs - 2, weight: .semibold))
            Text(text)
                .flixorFont(.micro)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, DS.Space.s8)
        .padding(.vertical, DS.Space.s4)
        .background(Capsule(style: .continuous).fill(tint.opacity(DS.Opacity.selected)))
    }

    private var commentBody: some View {
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            Text(displayText)
                .flixorParagraph(.body)
                .foregroundStyle(theme.textPrimary.opacity(DS.Opacity.strong))
                .lineLimit(isExpanded ? nil : 6)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .blur(radius: isHidden ? 7 : 0)
                .accessibilityHidden(isHidden)
                .overlay {
                    if isHidden {
                        Button(action: { withAnimation(DS.Motion.standard) { onRevealSpoiler() } }) {
                            Label("Contains spoilers. Click to reveal", systemImage: "eye.slash.fill")
                                .flixorFont(.footnote, weight: .semibold)
                                .foregroundStyle(theme.textPrimary)
                                .padding(.horizontal, DS.Space.s12)
                                .padding(.vertical, DS.Space.s8)
                                .background(Capsule(style: .continuous).fill(theme.scrim(DS.Opacity.scrimMedium)))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Reveal spoiler comment"))
                    }
                }

            if isLong && !isHidden {
                Button(isExpanded ? "Show Less" : "Read More", action: onToggleExpanded)
                    .buttonStyle(.plain)
                    .flixorFont(.footnote, weight: .semibold)
                    .foregroundStyle(theme.accentBright)
                    .accessibilityLabel(Text(isExpanded ? "Show less of this comment" : "Read the full comment"))
            }
        }
    }

    private var footer: some View {
        HStack(spacing: DS.Space.s16) {
            Label("\(comment.likes)", systemImage: "hand.thumbsup.fill")
                .accessibilityLabel(Text("\(comment.likes) likes"))
            if comment.replies > 0 {
                Label("\(comment.replies)", systemImage: "bubble.left.fill")
                    .accessibilityLabel(Text("\(comment.replies) replies"))
            }
        }
        .flixorFont(.caption, weight: .medium)
        .foregroundStyle(theme.textTertiary)
    }
}

// MARK: - Dates

private enum TraktCommentDate {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain = ISO8601DateFormatter()
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()
    private static let fullFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .short
        return f
    }()

    static func parse(_ string: String?) -> Date? {
        guard let string else { return nil }
        return fractional.date(from: string) ?? plain.date(from: string)
    }

    static func relative(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    static func full(_ date: Date) -> String {
        fullFormatter.string(from: date)
    }
}
