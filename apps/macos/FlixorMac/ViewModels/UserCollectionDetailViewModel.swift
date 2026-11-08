//
//  UserCollectionDetailViewModel.swift
//  FlixorMac
//
//  Pages a collection's sources into one de-duplicated grid. Each load takes one
//  page from every source that has more; a failed source is reported and left
//  out, and the others carry on.
//

import Foundation

@MainActor
final class UserCollectionDetailViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case loaded
        case empty
        case failed(String)
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var items: [MediaItem] = []
    @Published private(set) var isLoadingMore = false
    @Published private(set) var failures: [UserCollectionPreview.Failure] = []

    private struct SourceState {
        let source: UserCollectionSource
        var cursor: Int?
        var started = false
        var finished = false
        var failed = false
    }

    private var states: [SourceState] = []
    private var deduper = UserCollectionDeduper()
    private var isLoading = false
    /// Bumped on every restart so a stale load can't write into a new one.
    private var generation = 0

    var canLoadMore: Bool {
        states.contains { !$0.finished && !$0.failed }
    }

    /// Loads these sources. A no-op when they're already loaded, so coming back
    /// from a details page keeps the grid and its scroll position.
    func start(sources: [UserCollectionSource]) {
        guard states.map(\.source.kind) != sources.map(\.kind) else { return }
        generation += 1
        states = sources.map { SourceState(source: $0) }
        deduper = UserCollectionDeduper()
        items = []
        failures = []
        isLoading = false
        isLoadingMore = false
        phase = .loading
        Task { await loadNextPage() }
    }

    func itemAppeared(at index: Int, prefetchDistance: Int) {
        guard index >= items.count - prefetchDistance else { return }
        loadMore()
    }

    func loadMore() {
        guard canLoadMore, !isLoading else { return }
        Task { await loadNextPage() }
    }

    func retryFailedSources() {
        for index in states.indices { states[index].failed = false }
        failures = []
        if items.isEmpty { phase = .loading }
        Task { await loadNextPage() }
    }

    private func loadNextPage() async {
        guard !isLoading else { return }
        let targets = states.indices.filter { !states[$0].finished && !states[$0].failed }
        guard !targets.isEmpty else {
            settlePhase()
            return
        }

        isLoading = true
        isLoadingMore = !items.isEmpty
        let currentGeneration = generation
        let requests = targets.map { (index: $0, source: states[$0].source, cursor: states[$0].cursor) }

        var results: [Int: Result<UserCollectionSourcePage, Error>] = [:]
        await withTaskGroup(of: (Int, Result<UserCollectionSourcePage, Error>).self) { group in
            for request in requests {
                group.addTask {
                    do {
                        let page = try await UserCollectionSourceResolver.fetchPage(request.source, cursor: request.cursor)
                        return (request.index, .success(page))
                    } catch {
                        return (request.index, .failure(error))
                    }
                }
            }
            for await (index, result) in group {
                results[index] = result
            }
        }

        guard currentGeneration == generation else { return }

        // Applied in source order, so reordering sources reorders the grid.
        var added: [MediaItem] = []
        for index in targets {
            switch results[index] {
            case .success(let page):
                let fresh = page.items.filter { deduper.insert($0) }
                added.append(contentsOf: fresh)
                states[index].started = true
                states[index].cursor = page.nextCursor
                // No new titles means the source is done, or ignores paging.
                states[index].finished = page.nextCursor == nil || fresh.isEmpty
            case .failure(let error):
                states[index].failed = true
                failures.append(.init(
                    id: states[index].source.id,
                    sourceTitle: states[index].source.title,
                    message: UserCollectionSourceResolver.message(for: error)
                ))
            case nil:
                states[index].finished = true
            }
        }

        items.append(contentsOf: added)
        isLoading = false
        isLoadingMore = false
        settlePhase()
    }

    private func settlePhase() {
        if !items.isEmpty {
            phase = .loaded
        } else if let failure = failures.first {
            phase = .failed(failure.message)
        } else if !canLoadMore {
            phase = .empty
        }
    }
}
