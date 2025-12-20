/**
 * Interface for general key-value storage.
 * Platform implementations:
 * - Mobile: AsyncStorage
 * - Web: localStorage
 * - Native: UserDefaults
 */
export interface IStorage {
  get(key: string): Promise<string | null>;
  set(key: string, value: string): Promise<void>;
  remove(key: string): Promise<void>;
  clear(): Promise<void>;
}
