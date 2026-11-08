//
//  HomeViewModel+ContinueWatching.swift
//  FlixorMac
//
//  Continue Watching card actions: resume, start over, mark watched, remove,
//  go to details. Watch-state changes go through WatchStateService; the row
//  updates optimistically and a toast reports the result.
//

import SwiftUI

extension HomeViewModel {
    /// Continue Watching items in the order picked in settings.
    func continueWatchingItems(sortedBy sort: ContinueWatchingSort) -> [MediaItem] {
        sort.apply(to: continueWatchingItems)
    }

    func performContinueWatchingAction(_ action: ContinueWatchingAction, item: MediaItem) {
        switch action {
        case .resume:
            playFromContinueWatching(item)
        case .details:
            showItemDetails(item)
        case .startOver:
            Task { await startOverFromContinueWatching(item) }
        case .markWatched, .remove:
            Task { await removeFromContinueWatchingRow(item, action: action) }
        }
    }

    // MARK: - Private

    private func beginContinueWatchingAction(_ item: MediaItem) -> Bool {
        guard item.supportsContinueWatchingStateActions,
              !continueWatchingBusyIds.contains(item.id) else { return false }
        continueWatchingBusyIds.insert(item.id)
        return true
    }

    private func endContinueWatchingAction(_ item: MediaItem) {
        continueWatchingBusyIds.remove(item.id)
    }

    /// Resets progress everywhere, then plays from the beginning.
    private func startOverFromContinueWatching(_ item: MediaItem) async {
        guard beginContinueWatchingAction(item) else { return }
        let result = await WatchStateService.shared.startOver(item)
        endContinueWatchingAction(item)
        showToast(for: result)
        if result.isSuccess || result.isPartialSuccess {
            playFromContinueWatching(item.withoutResumePoint())
        }
    }

    /// Mark watched / remove: the card leaves the row right away and comes
    /// back if the action fails everywhere.
    private func removeFromContinueWatchingRow(_ item: MediaItem, action: ContinueWatchingAction) async {
        guard beginContinueWatchingAction(item) else { return }
        let originalIndex = continueWatchingItems.firstIndex { $0.id == item.id }

        withAnimation(DS.Motion.standard) {
            continueWatchingItems.removeAll { $0.id == item.id }
            if continueWatchingItems.isEmpty { continueWatchingState = .empty }
        }

        let result: WatchStateResult
        if action == .markWatched {
            result = await WatchStateService.shared.markWatched(item)
        } else {
            result = await WatchStateService.shared.removeFromContinueWatching(item)
        }
        endContinueWatchingAction(item)

        if !result.isSuccess && !result.isPartialSuccess,
           !continueWatchingItems.contains(where: { $0.id == item.id }) {
            withAnimation(DS.Motion.standard) {
                let index = min(originalIndex ?? 0, continueWatchingItems.count)
                continueWatchingItems.insert(item, at: index)
                continueWatchingState = .loaded
            }
        }
        showToast(for: result)
    }

    private func showToast(for result: WatchStateResult) {
        let type: ToastView.ToastType = result.isSuccess ? .success : (result.isPartialSuccess ? .info : .error)
        ToastManager.shared.show(result.message, type: type)
    }
}
