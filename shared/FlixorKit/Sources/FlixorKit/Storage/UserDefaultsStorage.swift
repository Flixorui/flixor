//
//  UserDefaultsStorage.swift
//  FlixorKit
//
//  General storage implementation using UserDefaults
//  Reference: packages/core/src/storage/IStorage.ts
//

import Foundation

// MARK: - UserDefaultsStorage

public class UserDefaultsStorage: StorageProtocol {
    private let defaults: UserDefaults
    private let prefix: String

    public init(
        defaults: UserDefaults = .standard,
        prefix: String = "flixor."
    ) {
        self.defaults = defaults
        self.prefix = prefix
    }

    private func prefixedKey(_ key: String) -> String {
        return "\(prefix)\(key)"
    }

    // MARK: - StorageProtocol

    public func get<T: Decodable>(_ key: String) async throws -> T? {
        let prefixedKey = prefixedKey(key)

        // Special case for String type
        if T.self == String.self {
            return defaults.string(forKey: prefixedKey) as? T
        }

        // Special case for Bool type
        if T.self == Bool.self {
            guard defaults.object(forKey: prefixedKey) != nil else { return nil }
            return defaults.bool(forKey: prefixedKey) as? T
        }

        // Special case for Int type
        if T.self == Int.self {
            guard defaults.object(forKey: prefixedKey) != nil else { return nil }
            return defaults.integer(forKey: prefixedKey) as? T
        }

        // Special case for Double type
        if T.self == Double.self {
            guard defaults.object(forKey: prefixedKey) != nil else { return nil }
            return defaults.double(forKey: prefixedKey) as? T
        }

        // For complex types, decode from Data
        guard let data = defaults.data(forKey: prefixedKey) else {
            return nil
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    public func set<T: Encodable>(_ key: String, value: T?) async throws {
        let prefixedKey = prefixedKey(key)

        guard let value = value else {
            defaults.removeObject(forKey: prefixedKey)
            return
        }

        // Special case for basic types
        if let stringValue = value as? String {
            defaults.set(stringValue, forKey: prefixedKey)
            return
        }

        if let boolValue = value as? Bool {
            defaults.set(boolValue, forKey: prefixedKey)
            return
        }

        if let intValue = value as? Int {
            defaults.set(intValue, forKey: prefixedKey)
            return
        }

        if let doubleValue = value as? Double {
            defaults.set(doubleValue, forKey: prefixedKey)
            return
        }

        // For complex types, encode to Data
        let data = try JSONEncoder().encode(value)
        defaults.set(data, forKey: prefixedKey)
    }

    public func remove(_ key: String) async throws {
        defaults.removeObject(forKey: prefixedKey(key))
    }

    public func clear() async throws {
        // Get all keys with our prefix and remove them
        let allKeys = defaults.dictionaryRepresentation().keys
        for key in allKeys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }
}
