//
//  MpvConfigModels.swift
//  FlixorMac
//
//  Models for custom MPV configuration entries and presets
//  Based on plezy implementation
//

import Foundation

/// Represents a single MPV configuration entry
struct MpvConfigEntry: Codable, Identifiable, Equatable {
    let id: UUID
    var key: String
    var value: String
    var isEnabled: Bool

    init(id: UUID = UUID(), key: String, value: String, isEnabled: Bool = true) {
        self.id = id
        self.key = key
        self.value = value
        self.isEnabled = isEnabled
    }

    func copyWith(key: String? = nil, value: String? = nil, isEnabled: Bool? = nil) -> MpvConfigEntry {
        return MpvConfigEntry(
            id: self.id,
            key: key ?? self.key,
            value: value ?? self.value,
            isEnabled: isEnabled ?? self.isEnabled
        )
    }
}

/// Represents a saved preset of MPV configurations
struct MpvPreset: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var entries: [MpvConfigEntry]
    let createdAt: Date

    init(id: UUID = UUID(), name: String, entries: [MpvConfigEntry], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.entries = entries
        self.createdAt = createdAt
    }

    var entriesCount: Int {
        entries.count
    }

    var enabledEntriesCount: Int {
        entries.filter { $0.isEnabled }.count
    }
}
