//
//  DownloadStorageService.swift
//  FlixorMac
//
//  Persistence for downloads using UserDefaults with JSON encoding
//

import Foundation

class DownloadStorageService {
    static let shared = DownloadStorageService()

    private let downloadsKey = "flixor.downloads.items"
    private let queueKey = "flixor.downloads.queue"

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {}

    // MARK: - Completed Downloads

    /// Load all completed downloads
    func loadDownloads() -> [DownloadedItem] {
        guard let data = UserDefaults.standard.data(forKey: downloadsKey) else {
            return []
        }

        do {
            let items = try decoder.decode([DownloadedItem].self, from: data)
            return items
        } catch {
            print("[DownloadStorageService] Failed to decode downloads: \(error)")
            return []
        }
    }

    /// Save all completed downloads
    func saveDownloads(_ items: [DownloadedItem]) {
        do {
            let data = try encoder.encode(items)
            UserDefaults.standard.set(data, forKey: downloadsKey)
        } catch {
            print("[DownloadStorageService] Failed to encode downloads: \(error)")
        }
    }

    /// Add a completed download
    func addCompletedDownload(_ item: DownloadedItem) {
        var items = loadDownloads()
        // Remove existing if any (update scenario)
        items.removeAll { $0.id == item.id }
        items.append(item)
        saveDownloads(items)
    }

    /// Remove a download by ID
    func removeDownload(id: String) {
        var items = loadDownloads()
        items.removeAll { $0.id == id }
        saveDownloads(items)
    }

    /// Get a specific download by ID
    func getDownload(id: String) -> DownloadedItem? {
        return loadDownloads().first { $0.id == id }
    }

    /// Update a download
    func updateDownload(_ item: DownloadedItem) {
        var items = loadDownloads()
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
            saveDownloads(items)
        }
    }

    // MARK: - Download Queue (In-Progress)

    /// Load the download queue
    func loadQueue() -> [DownloadTask] {
        guard let data = UserDefaults.standard.data(forKey: queueKey) else {
            return []
        }

        do {
            let tasks = try decoder.decode([DownloadTask].self, from: data)
            return tasks
        } catch {
            print("[DownloadStorageService] Failed to decode queue: \(error)")
            return []
        }
    }

    /// Save the download queue
    func saveQueue(_ tasks: [DownloadTask]) {
        do {
            let data = try encoder.encode(tasks)
            UserDefaults.standard.set(data, forKey: queueKey)
        } catch {
            print("[DownloadStorageService] Failed to encode queue: \(error)")
        }
    }

    /// Add a task to the queue
    func addToQueue(_ task: DownloadTask) {
        var tasks = loadQueue()
        // Remove existing if any
        tasks.removeAll { $0.id == task.id }
        tasks.append(task)
        saveQueue(tasks)
    }

    /// Remove a task from the queue
    func removeFromQueue(id: String) {
        var tasks = loadQueue()
        tasks.removeAll { $0.id == id }
        saveQueue(tasks)
    }

    /// Update a task in the queue
    func updateQueueTask(_ task: DownloadTask) {
        var tasks = loadQueue()
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
            saveQueue(tasks)
        }
    }

    /// Get a specific task from the queue
    func getQueueTask(id: String) -> DownloadTask? {
        return loadQueue().first { $0.id == id }
    }

    // MARK: - Clear All

    /// Clear all downloads data (for debugging/reset)
    func clearAll() {
        UserDefaults.standard.removeObject(forKey: downloadsKey)
        UserDefaults.standard.removeObject(forKey: queueKey)
        print("[DownloadStorageService] Cleared all download data")
    }
}
