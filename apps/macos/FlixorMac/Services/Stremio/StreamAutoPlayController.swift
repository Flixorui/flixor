//
//  StreamAutoPlayController.swift
//  FlixorMac
//
//  Runs the "Finding a source…" state between pressing Play on addon content and
//  either starting playback or opening the sources page.
//

import AppKit
import Foundation

@MainActor
final class StreamAutoPlayController: ObservableObject {
    /// Title being looked up; nil when idle.
    @Published private(set) var findingTitle: String?

    private var task: Task<Void, Never>?
    private var showSourcesNow: (() -> Void)?
    private var wantsSourcesPage = false

    /// Holding Option while pressing Play always opens the sources page.
    static var isPickerModifierHeld: Bool {
        NSEvent.modifierFlags.contains(.option)
    }

    /// Shows the finding state while the title's addon id is still being resolved.
    func begin(title: String) {
        cancel()
        findingTitle = title
    }

    /// Looks for a source. No-op if the state was dismissed since `begin`.
    func run(
        destination: StremioSourcesDestination,
        action: StremioPlayAction,
        onPlay: @escaping (PlayerDestination) -> Void,
        onShowSources: @escaping (StremioSourcesDestination) -> Void
    ) {
        guard findingTitle != nil else { return }
        guard !wantsSourcesPage else {
            cancel()
            onShowSources(destination)
            return
        }

        task?.cancel()
        showSourcesNow = { onShowSources(destination) }
        task = Task { [weak self] in
            let outcome = await StremioSourcesViewModel(destination: destination).findAutomaticSource(action: action)
            guard let self, !Task.isCancelled else { return }
            self.cancel()

            switch outcome {
            case .play(let player):
                onPlay(player)
            case .showSources(let notice):
                var fallback = destination
                fallback.autoSelectNotice = notice
                onShowSources(fallback)
            }
        }
    }

    /// Stops looking and opens the sources page (as soon as the title has resolved).
    func chooseSourceInstead() {
        guard let showSourcesNow else {
            wantsSourcesPage = true
            return
        }
        cancel()
        showSourcesNow()
    }

    /// Stops looking and returns to the page as it was.
    func cancel() {
        task?.cancel()
        task = nil
        showSourcesNow = nil
        wantsSourcesPage = false
        findingTitle = nil
    }
}
