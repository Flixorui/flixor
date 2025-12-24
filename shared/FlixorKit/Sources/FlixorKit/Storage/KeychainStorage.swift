//
//  KeychainStorage.swift
//  FlixorKit
//
//  Secure storage implementation using Keychain
//  Reference: packages/core/src/storage/ISecureStorage.ts
//

import Foundation
import Security

// MARK: - KeychainStorage

public class KeychainStorage: SecureStorageProtocol {
    private let serviceName: String

    public init(serviceName: String = "com.flixor.keychain") {
        self.serviceName = serviceName
    }

    // MARK: - SecureStorageProtocol

    public func get<T: Decodable>(_ key: String) async throws -> T? {
        print("🔐 [Keychain] Getting \(key)...")
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                print("ℹ️ [Keychain] \(key) not found")
                return nil
            }
            print("❌ [Keychain] Failed to get \(key): status \(status)")
            throw KeychainError.unhandledError(status: status)
        }

        guard let data = result as? Data else {
            print("⚠️ [Keychain] \(key) returned nil data")
            return nil
        }

        print("✅ [Keychain] Found \(key) (\(data.count) bytes)")

        // Special case for String type
        if T.self == String.self {
            return String(data: data, encoding: .utf8) as? T
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    public func set<T: Encodable>(_ key: String, value: T) async throws {
        let data: Data
        if let stringValue = value as? String {
            guard let stringData = stringValue.data(using: .utf8) else {
                throw KeychainError.encodingError
            }
            data = stringData
        } else {
            data = try JSONEncoder().encode(value)
        }

        print("🔐 [Keychain] Saving \(key) (\(data.count) bytes)")

        // Try to delete existing item first
        try? await remove(key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            print("❌ [Keychain] Failed to save \(key): status \(status)")
            throw KeychainError.unhandledError(status: status)
        }
        print("✅ [Keychain] Saved \(key) successfully")
    }

    public func remove(_ key: String) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status: status)
        }
    }

    // MARK: - Additional Methods

    /// Clear all items for this service
    public func clearAll() async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status: status)
        }
    }
}

// MARK: - Errors

public enum KeychainError: Error, LocalizedError {
    case encodingError
    case unhandledError(status: OSStatus)

    public var errorDescription: String? {
        switch self {
        case .encodingError:
            return "Failed to encode value for Keychain storage"
        case .unhandledError(let status):
            return "Keychain error: \(status)"
        }
    }
}
