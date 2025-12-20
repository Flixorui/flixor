/**
 * Interface for secure/encrypted storage.
 * Used for sensitive data like auth tokens.
 * Platform implementations:
 * - Mobile: expo-secure-store
 * - Web: localStorage (no true secure storage in browser)
 * - Native: Keychain
 */
export interface ISecureStorage {
  /**
   * Get a value from secure storage
   * Implementation should JSON.parse the stored string
   */
  get<T = string>(key: string): Promise<T | null>;

  /**
   * Store a value in secure storage
   * Implementation should JSON.stringify objects before storing
   */
  set<T = string>(key: string, value: T): Promise<void>;

  /**
   * Remove a value from secure storage
   */
  remove(key: string): Promise<void>;
}
