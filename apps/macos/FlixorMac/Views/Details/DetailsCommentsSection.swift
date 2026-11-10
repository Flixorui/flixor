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
    /// The comment open in the popup, as an index into `comments`.
    @Published var selectedIndex: Int?

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

    var selectedComment: TraktComment? {
        guard let selectedIndex, comments.indices.contains(selectedIndex) else { return nil }
        return comments[selectedIndex]
    }

    var canSelectPrevious: Bool { (selectedIndex ?? 0) > 0 }

    var canSelectNext: Bool {
        guard let selectedIndex else { return false }
        return selectedIndex + 1 < comments.count || hasMore
    }

    func selectPrevious() {
        guard let selectedIndex, selectedIndex > 0 else { return }
        self.selectedIndex = selectedIndex - 1
    }

    func selectNext() async {
        guard let index = selectedIndex else { return }
        if index + 1 >= comments.count { await loadMore() }
        // The popup may have been closed during the load.
        guard selectedIndex == index, index + 1 < comments.count else { return }
        selectedIndex = index + 1
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
        selectedIndex = nil
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

    var body: some View {
        VStack(alignment: .leading, spacing: DetailsSectionStyle.headingGap) {
            header

            switch model.phase {
            case .idle, .loading:
                DetailsHorizontalRow {
                    HStack(spacing: DS.Space.s12) {
                        ForEach(0..<3, id: \.self) { _ in CommentPlaceholderCard() }
                    }
                }
                .disabled(true)
                .accessibilityLabel(Text("Loading comments…"))
            case .failed(let message):
                stateMessage(icon: "exclamationmark.bubble", title: message, actionTitle: String(localized: "Try Again")) {
                    Task { await model.retry() }
                }
            case .loaded:
                if model.comments.isEmpty {
                    stateMessage(icon: "text.bubble", title: String(localized: "No comments on Trakt yet."), actionTitle: nil, action: nil)
                } else {
                    commentsRow
                }
            }
        }
        .task(id: target) {
            await model.load(target: target)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.controlGap) {
            DetailsSectionHeading("Comments")
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
            // Neutral, like the rest of the UI: red is for progress and "on".
            .tint(SettingsChrome.neutralTint)
            .disabled(model.phase == .loading)
            .accessibilityLabel(Text("Sort comments"))
        }
    }

    private var commentsRow: some View {
        DetailsHorizontalRow {
            LazyHStack(alignment: .top, spacing: DS.Space.s12) {
                ForEach(Array(model.comments.enumerated()), id: \.element.id) { index, comment in
                    TraktCommentCard(comment: comment) {
                        model.selectedIndex = index
                    }
                    .onAppear {
                        if index >= model.comments.count - 3 {
                            Task { await model.loadMore() }
                        }
                    }
                }

                if model.isLoadingMore {
                    CommentPlaceholderCard()
                } else if let error = model.loadMoreError {
                    CommentRetryCard(message: error) {
                        Task { await model.loadMore() }
                    }
                }
            }
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

// MARK: - Comment Text

private extension TraktComment {
    var authorName: String {
        if let name = user?.name, !name.isEmpty { return name }
        return user?.username ?? String(localized: "Trakt user")
    }

    /// Whole comment flagged as spoiler, or inline [spoiler] tags in the text.
    var hasSpoilerContent: Bool {
        spoiler || comment.range(of: "[spoiler]", options: .caseInsensitive) != nil
    }

    var displayText: String {
        comment
            .replacingOccurrences(of: "[spoiler]", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "[/spoiler]", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var likesLabel: String {
        likes == 1 ? String(localized: "1 like") : String(localized: "\(likes) likes")
    }

    /// yyyy-MM-dd.
    var shortDate: String? {
        createdAt.map { String($0.prefix(10)) }
    }
}

// MARK: - Comment Cards

private enum CommentCardMetrics {
    static let size = CGSize(width: 340, height: 210)
}

private struct TraktCommentCard: View {
    let comment: TraktComment
    let onOpen: () -> Void

    @Environment(\.flixorTheme) private var theme
    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: DS.Space.s8) {
                Text(verbatim: comment.authorName)
                    .flixorFont(.callout, weight: .semibold)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)

                if comment.review {
                    CommentChip(text: String(localized: "Review"))
                }

                Group {
                    if comment.hasSpoilerContent {
                        Text("This comment contains spoilers.")
                            .foregroundStyle(theme.warning)
                    } else {
                        Text(verbatim: comment.displayText)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                .flixorParagraph(.body)
                .lineLimit(5)
                .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                CommentMeta(comment: comment)
            }
            .padding(DS.Space.s16)
            .frame(width: CommentCardMetrics.size.width, height: CommentCardMetrics.size.height, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(isHovered ? theme.hoverFill : theme.surfaceOverlay)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .strokeBorder(isHovered ? theme.separatorStrong : theme.separator, lineWidth: DS.Border.thin)
            )
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(DS.Motion.quick, value: isHovered)
        .accessibilityLabel(Text("Open comment by \(comment.authorName)"))
    }
}

private struct CommentChip: View {
    let text: String

    @Environment(\.flixorTheme) private var theme

    var body: some View {
        Text(verbatim: text)
            .flixorFont(.caption, weight: .medium)
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, DS.Space.s10)
            .padding(.vertical, DS.Space.s4)
            .background(Capsule(style: .continuous).fill(theme.hoverFill))
    }
}

private struct CommentMeta: View {
    let comment: TraktComment

    @Environment(\.flixorTheme) private var theme

    var body: some View {
        HStack(spacing: DS.Space.s8) {
            if let rating = comment.userRating {
                Text("\(rating)/10")
            }
            Text(verbatim: comment.likesLabel)
        }
        .flixorFont(.caption, weight: .medium)
        .foregroundStyle(theme.textTertiary)
        .lineLimit(1)
    }
}

private struct CommentPlaceholderCard: View {
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s10) {
            line(width: 96, height: 14)
            line(width: nil, height: 12).padding(.top, DS.Space.s6)
            line(width: nil, height: 12)
            line(width: 210, height: 12)
            Spacer(minLength: 0)
            line(width: 64, height: 10)
        }
        .padding(DS.Space.s16)
        .frame(width: CommentCardMetrics.size.width, height: CommentCardMetrics.size.height, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(theme.surfaceOverlay)
        )
        .accessibilityHidden(true)
    }

    private func line(width: CGFloat?, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: DS.Radius.r4, style: .continuous)
            .fill(theme.hoverFill)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

private struct CommentRetryCard: View {
    let message: String
    let onRetry: () -> Void

    @Environment(\.flixorTheme) private var theme

    var body: some View {
        VStack(spacing: DS.Space.s12) {
            Text(verbatim: message)
                .flixorFont(.footnote)
                .foregroundStyle(theme.danger)
                .multilineTextAlignment(.center)
            Button("Retry", action: onRetry)
                .controlSize(.small)
                .accessibilityLabel(Text("Show more comments"))
        }
        .padding(DS.Space.s16)
        .frame(width: CommentCardMetrics.size.width, height: CommentCardMetrics.size.height)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(theme.surfaceOverlay)
        )
    }
}

// MARK: - Comment Popup

/// One full comment over the page, with previous/next through the whole list.
struct DetailsCommentPopup: View {
    @ObservedObject var model: DetailsCommentsModel

    @Environment(\.flixorTheme) private var theme
    @Environment(\.windowMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func close() {
        model.selectedIndex = nil
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if let comment = model.selectedComment, let index = model.selectedIndex {
                theme.scrim(DS.Opacity.scrimMedium)
                    .ignoresSafeArea()
                    .onTapGesture { close() }
                    .transition(.opacity)
                    .accessibilityHidden(true)

                panel(comment: comment, index: index)
                    .inPageModal(onDismiss: close)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(reduceMotion ? DS.Motion.quick : DS.Motion.standard, value: model.selectedIndex != nil)
    }

    private func panel(comment: TraktComment, index: Int) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            Capsule(style: .continuous)
                .fill(theme.separatorStrong)
                .frame(width: 40, height: 4)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            header(comment: comment, index: index)

            if comment.review {
                CommentChip(text: String(localized: "Review"))
            }

            ViewThatFits(in: .vertical) {
                commentText(comment)
                ScrollView { commentText(comment) }
            }
            .id(comment.id)

            HStack {
                CommentMeta(comment: comment)
                Spacer()
                if let date = comment.shortDate {
                    Text(verbatim: date)
                        .flixorFont(.caption, weight: .medium)
                        .foregroundStyle(theme.textTertiary)
                }
            }
        }
        .padding(.horizontal, DS.Space.s24)
        .padding(.top, DS.Space.s12)
        .padding(.bottom, DS.Space.s24)
        .frame(width: min(720, metrics.width - DS.Space.s40))
        .frame(maxHeight: metrics.height * 0.7)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            UnevenTopRoundedRectangle(radius: DS.Radius.r24)
                .fill(theme.surfaceElevated)
        )
        .overlay(
            UnevenTopRoundedRectangle(radius: DS.Radius.r24)
                .stroke(theme.separator, lineWidth: DS.Border.thin)
        )
        .contentShape(Rectangle())
        .onTapGesture {} // A click on the panel must not reach the scrim.
        .accessibilityAddTraits(.isModal)
    }

    private func header(comment: TraktComment, index: Int) -> some View {
        HStack(spacing: DS.Space.s8) {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text(verbatim: comment.authorName)
                    .flixorFont(.bodyLarge, weight: .semibold)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                if let username = comment.user?.username, !username.isEmpty {
                    Text(verbatim: "@\(username)")
                        .flixorFont(.footnote)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: DS.Space.s12)

            pagerButton(
                icon: "chevron.left",
                label: "Previous comment",
                isEnabled: model.canSelectPrevious,
                shortcut: .leftArrow,
                action: { model.selectPrevious() }
            )

            Text(verbatim: "\(index + 1) / \(max(model.totalCount, model.comments.count))")
                .flixorFont(.footnote, weight: .medium)
                .foregroundStyle(theme.textSecondary)
                .monospacedDigit()

            pagerButton(
                icon: "chevron.right",
                label: "Next comment",
                isEnabled: model.canSelectNext,
                shortcut: .rightArrow,
                action: { Task { await model.selectNext() } }
            )
        }
    }

    private func pagerButton(
        icon: String,
        label: LocalizedStringKey,
        isEnabled: Bool,
        shortcut: KeyEquivalent,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.flixorIcon(DS.Icon.sm, weight: .semibold))
                .foregroundStyle(isEnabled ? theme.textPrimary : theme.textTertiary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(theme.hoverFill.opacity(isEnabled ? 1 : 0.4)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .keyboardShortcut(shortcut, modifiers: [])
        .accessibilityLabel(Text(label))
    }

    @ViewBuilder
    private func commentText(_ comment: TraktComment) -> some View {
        if comment.hasSpoilerContent && !model.revealedSpoilers.contains(comment.id) {
            Button {
                model.revealedSpoilers.insert(comment.id)
            } label: {
                Text("This comment contains spoilers. Click to reveal.")
                    .flixorParagraph(.bodyLarge)
                    .foregroundStyle(theme.warning)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Reveal spoiler comment"))
        } else {
            Text(verbatim: comment.displayText)
                .flixorParagraph(.bodyLarge)
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }
}

/// Rounded on top, square at the bottom, where the panel meets the window edge.
private struct UnevenTopRoundedRectangle: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.minY),
            tangent2End: CGPoint(x: rect.minX + radius, y: rect.minY),
            radius: radius
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
            tangent2End: CGPoint(x: rect.maxX, y: rect.minY + radius),
            radius: radius
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}
