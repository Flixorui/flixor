//
//  StremioResumeStore.swift
//  FlixorMac
//
//  Local resume state for generic stream playback.
//

import Foundation

actor StremioResumeStore {
    static let shared = StremioResumeStore()

    private let storage = StremioStorage.shared

    func get(contentKey: String) async -> ResumeState? {
        let index = await storage.resumeStateIndex()
        return index[contentKey]
    }

    func save(_ state: ResumeState) async {
        var index = await storage.resumeStateIndex()
        index[state.contentKey] = state
        await storage.setResumeStateIndex(index)
    }

    func remove(contentKey: String) async {
        var index = await storage.resumeStateIndex()
        index.removeValue(forKey: contentKey)
        await storage.setResumeStateIndex(index)
    }
}
