//
//  DownloadManager.swift
//  FlixorMac
//
//  Main download orchestrator - manages download queue, progress, and state
//
//  Uses URLSession.downloadTask() for memory-efficient streaming to disk
//

import Foundation
import FlixorKit
import Combine

@MainActor
class DownloadManager: NSObject, ObservableObject {
    // MARK: - Singleton

    static let shared = DownloadManager()

    // MARK: - Published State

    @Published private(set) var activeTasks: [DownloadTask] = []
    @Published private(set) var downloadedItems: [DownloadedItem] = []

    // MARK: - Computed Properties

    /// All downloaded movies sorted by download date (newest first)
    var downloadedMovies: [DownloadedItem] {
        downloadedItems
            .filter { $0.type == .movie }
            .sorted { $0.downloadedAt > $1.downloadedAt }
    }

    /// All downloaded TV shows grouped by show
    var downloadedShows: [DownloadedShow] {
        let episodes = downloadedItems.filter { $0.type == .episode }
        var showsMap: [String: DownloadedShow] = [:]

        for ep in episodes {
            guard let showKey = ep.grandparentRatingKey else { continue }
            let key = "\(ep.serverId):\(showKey)"

            if showsMap[key] == nil {
                showsMap[key] = DownloadedShow(
                    serverId: ep.serverId,
                    grandparentRatingKey: showKey,
                    title: ep.grandparentTitle ?? "Unknown Show",
                    year: ep.year,
                    artworkPath: ep.artworkPath,
                    episodes: []
                )
            }
            showsMap[key]?.episodes.append(ep)
        }

        return showsMap.values
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Check if there are any active downloads
    var hasActiveDownloads: Bool {
        !activeTasks.isEmpty
    }

    // MARK: - Private Properties

    private var urlSession: URLSession!
    private var activeDownloadTasks: [String: URLSessionDownloadTask] = [:]
    private var downloadProgressObservers: [String: NSKeyValueObservation] = [:]
    private var taskToGlobalKey: [Int: String] = [:]  // Maps taskIdentifier to globalKey

    // Resume data for interrupted downloads
    private var resumeDataStore: [String: Data] = [:]
    private var lastProgressStore: [String: Int64] = [:]  // Track last progress to detect if stuck
    private var stuckRetryCount: [String: Int] = [:]  // Only count retries when no progress made
    private let maxStuckRetries = 5  // Only give up if stuck (no progress) for this many retries

    private let fileService = DownloadFileService.shared
    private let storageService = DownloadStorageService.shared

    // MARK: - Initialization

    private override init() {
        super.init()

        // Configure URLSession with delegate for large file downloads
        let config = URLSessionConfiguration.default
        config.allowsCellularAccess = true
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.timeoutIntervalForRequest = 60 * 60  // 1 hour
        config.timeoutIntervalForResource = 60 * 60 * 24  // 24 hours for large files
        config.waitsForConnectivity = true
        config.httpMaximumConnectionsPerHost = 1  // Single connection for downloads

        // Use a dedicated queue for download callbacks (not main queue)
        let delegateQueue = OperationQueue()
        delegateQueue.name = "com.flixor.downloadManager"
        delegateQueue.maxConcurrentOperationCount = 1

        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)

        // Load persisted state
        loadPersistedState()
    }

    // MARK: - State Loading

    private func loadPersistedState() {
        downloadedItems = storageService.loadDownloads()
        activeTasks = storageService.loadQueue()

        // Reset any downloads that were "downloading" to "queued" (app was closed mid-download)
        for i in activeTasks.indices {
            if activeTasks[i].status == .downloading {
                activeTasks[i].status = .queued
            }
        }
        storageService.saveQueue(activeTasks)

        // Start processing the queue
        processQueue()
    }

    // MARK: - Public API

    /// Queue a download for a media item
    func queueDownload(
        ratingKey: String,
        serverId: String,
        type: DownloadMediaType,
        title: String,
        year: Int?,
        thumb: String?,
        grandparentTitle: String?,
        grandparentRatingKey: String?,
        parentIndex: Int?,
        index: Int?
    ) {
        let globalKey = "\(serverId):\(ratingKey)"

        // Check if already downloaded
        if isDownloaded(globalKey) {
            print("[DownloadManager] Already downloaded: \(globalKey)")
            return
        }

        // Check if already in queue
        if activeTasks.contains(where: { $0.id == globalKey }) {
            print("[DownloadManager] Already in queue: \(globalKey)")
            return
        }

        // Create download task
        let task = DownloadTask(
            id: globalKey,
            serverId: serverId,
            ratingKey: ratingKey,
            type: type,
            status: .queued,
            progress: 0,
            downloadedBytes: 0,
            totalBytes: 0,
            errorMessage: nil,
            title: title,
            year: year,
            thumb: thumb,
            grandparentTitle: grandparentTitle,
            grandparentRatingKey: grandparentRatingKey,
            parentIndex: parentIndex,
            index: index
        )

        activeTasks.append(task)
        storageService.saveQueue(activeTasks)

        print("[DownloadManager] Queued download: \(globalKey)")

        // Start processing
        processQueue()
    }

    /// Check if an item is downloaded
    func isDownloaded(_ globalKey: String) -> Bool {
        downloadedItems.contains { $0.id == globalKey }
    }

    /// Check if an item is currently downloading or queued
    func isDownloading(_ globalKey: String) -> Bool {
        activeTasks.contains { $0.id == globalKey && ($0.status == .downloading || $0.status == .queued) }
    }

    /// Get the current progress for a download
    func getProgress(_ globalKey: String) -> DownloadTask? {
        activeTasks.first { $0.id == globalKey }
    }

    /// Get a downloaded item by global key
    func getDownloadedItem(_ globalKey: String) -> DownloadedItem? {
        downloadedItems.first { $0.id == globalKey }
    }

    /// Pause a download
    func pauseDownload(_ globalKey: String) {
        if let downloadTask = activeDownloadTasks[globalKey] {
            downloadTask.suspend()
        }

        if let index = activeTasks.firstIndex(where: { $0.id == globalKey }) {
            activeTasks[index].status = .paused
            storageService.saveQueue(activeTasks)
        }

        print("[DownloadManager] Paused: \(globalKey)")
    }

    /// Resume a paused download
    func resumeDownload(_ globalKey: String) {
        if let downloadTask = activeDownloadTasks[globalKey] {
            downloadTask.resume()
        }

        if let index = activeTasks.firstIndex(where: { $0.id == globalKey }) {
            activeTasks[index].status = .downloading
            storageService.saveQueue(activeTasks)
        }

        print("[DownloadManager] Resumed: \(globalKey)")

        processQueue()
    }

    /// Cancel a download
    func cancelDownload(_ globalKey: String) {
        // Cancel URLSession task
        if let downloadTask = activeDownloadTasks[globalKey] {
            downloadTask.cancel()
            activeDownloadTasks.removeValue(forKey: globalKey)
        }

        // Remove progress observer
        downloadProgressObservers[globalKey]?.invalidate()
        downloadProgressObservers.removeValue(forKey: globalKey)

        // Remove from active tasks
        activeTasks.removeAll { $0.id == globalKey }
        storageService.saveQueue(activeTasks)

        print("[DownloadManager] Cancelled: \(globalKey)")

        // Process next in queue
        processQueue()
    }

    /// Delete a completed download
    func deleteDownload(_ globalKey: String) {
        guard let item = downloadedItems.first(where: { $0.id == globalKey }) else { return }

        // Delete files
        do {
            try fileService.deleteDownload(item)
        } catch {
            print("[DownloadManager] Failed to delete files: \(error)")
        }

        // Remove from state
        downloadedItems.removeAll { $0.id == globalKey }
        storageService.removeDownload(id: globalKey)

        print("[DownloadManager] Deleted: \(globalKey)")
    }

    /// Retry a failed download (manual retry resets stuck count)
    func retryDownload(_ globalKey: String) {
        if let index = activeTasks.firstIndex(where: { $0.id == globalKey && $0.status == .failed }) {
            // Reset stuck count for manual retry
            stuckRetryCount[globalKey] = 0
            lastProgressStore[globalKey] = 0

            // If we have resume data, use it
            if resumeDataStore[globalKey] != nil {
                activeTasks[index].status = .downloading
                activeTasks[index].errorMessage = nil
                storageService.saveQueue(activeTasks)

                print("[DownloadManager] Retrying with resume data: \(globalKey)")
                retryDownloadWithResumeData(globalKey)
            } else {
                // No resume data, restart from beginning
                activeTasks[index].status = .queued
                activeTasks[index].errorMessage = nil
                activeTasks[index].progress = 0
                activeTasks[index].downloadedBytes = 0
                storageService.saveQueue(activeTasks)

                print("[DownloadManager] Retrying from start: \(globalKey)")
                processQueue()
            }
        }
    }

    // MARK: - Queue Processing

    private func processQueue() {
        // Only download one at a time for simplicity
        guard !activeTasks.contains(where: { $0.status == .downloading }) else {
            return
        }

        // Find next queued task
        guard let nextTask = activeTasks.first(where: { $0.status == .queued }) else {
            return
        }

        startDownload(nextTask)
    }

    private func startDownload(_ task: DownloadTask) {
        Task {
            await performDownload(task)
        }
    }

    private func performDownload(_ task: DownloadTask) async {
        var task = task

        // Update status to downloading
        task.status = .downloading
        updateTask(task)

        do {
            // 1. Get Plex server
            guard let plexServer = FlixorCore.shared.plexServer else {
                throw DownloadError.noServer
            }

            // 2. Fetch metadata to get the actual media file URL
            let metadata = try await plexServer.getMetadata(ratingKey: task.ratingKey)

            // 3. Get the Part key (actual download path)
            guard let media = metadata.Media?.first,
                  let part = media.Part?.first,
                  let partKey = part.key else {
                throw DownloadError.downloadFailed("No media file found for this item")
            }

            // 4. Construct the download URL using the part key
            guard let baseUrl = FlixorCore.shared.connection?.uri,
                  let token = FlixorCore.shared.getPlexToken() else {
                throw DownloadError.noServer
            }
            let downloadUrl = "\(baseUrl)\(partKey)?X-Plex-Token=\(token)"

            print("[DownloadManager] Download URL: \(downloadUrl)")

            guard let url = URL(string: downloadUrl) else {
                throw DownloadError.invalidUrl
            }

            // 5. Determine file extension from part container or file path
            let ext = part.container ?? fileService.extractExtension(from: partKey)

            // 4. Compute destination path (RELATIVE)
            let relativePath: String
            if task.type == .movie {
                relativePath = fileService.moviePath(title: task.title, year: task.year, ext: ext)
            } else {
                relativePath = fileService.episodePath(
                    show: task.grandparentTitle ?? "Unknown",
                    season: task.parentIndex ?? 1,
                    episode: task.index ?? 1,
                    title: task.title,
                    ext: ext
                )
            }

            // 5. Ensure directory exists
            try fileService.ensureDirectoryExists(for: relativePath)

            // 6. Create download request with Plex headers
            var request = URLRequest(url: url)
            request.timeoutInterval = 60 * 60 * 4  // 4 hour timeout for large files

            // Add required Plex headers (same as player uses)
            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            request.setValue("FlixorMac", forHTTPHeaderField: "X-Plex-Client-Identifier")
            request.setValue("Flixor", forHTTPHeaderField: "X-Plex-Product")
            request.setValue(appVersion, forHTTPHeaderField: "X-Plex-Version")
            request.setValue("macOS", forHTTPHeaderField: "X-Plex-Platform")
            request.setValue("Generic", forHTTPHeaderField: "X-Plex-Client-Profile-Name")

            if let plexToken = FlixorCore.shared.getPlexToken() {
                request.setValue(plexToken, forHTTPHeaderField: "X-Plex-Token")
            }

            // 7. Start the download task
            let downloadTask = urlSession.downloadTask(with: request)
            activeDownloadTasks[task.id] = downloadTask
            taskToGlobalKey[downloadTask.taskIdentifier] = task.id

            // Store the relative path for later use
            UserDefaults.standard.set(relativePath, forKey: "download.path.\(task.id)")

            // 8. Observe progress
            let observation = downloadTask.progress.observe(
                \Progress.fractionCompleted,
                options: [.new]
            ) { [weak self] (progress: Progress, _) in
                Task { @MainActor [weak self] in
                    self?.handleProgressUpdate(
                        taskId: task.id,
                        progress: progress.fractionCompleted,
                        bytes: progress.completedUnitCount,
                        total: progress.totalUnitCount
                    )
                }
            }
            downloadProgressObservers[task.id] = observation

            // 9. Start the download
            downloadTask.resume()

            print("[DownloadManager] Started download: \(task.id)")

        } catch {
            print("[DownloadManager] Download failed: \(error)")
            task.status = .failed
            task.errorMessage = error.localizedDescription
            updateTask(task)
            processQueue()
        }
    }

    // MARK: - Progress Updates

    private func handleProgressUpdate(taskId: String, progress: Double, bytes: Int64, total: Int64) {
        guard let index = activeTasks.firstIndex(where: { $0.id == taskId }) else { return }

        activeTasks[index].progress = progress
        activeTasks[index].downloadedBytes = bytes
        activeTasks[index].totalBytes = total

        // Don't save to disk on every update (too slow), just update memory
        // Storage is saved on completion/failure
    }

    private func updateTask(_ task: DownloadTask) {
        if let index = activeTasks.firstIndex(where: { $0.id == task.id }) {
            activeTasks[index] = task
        }
        storageService.saveQueue(activeTasks)
    }

    // MARK: - Download Completion

    private func handleDownloadCompletion(taskId: String, tempFileUrl: URL) async {
        guard let index = activeTasks.firstIndex(where: { $0.id == taskId }) else {
            print("[DownloadManager] Task not found for completion: \(taskId)")
            return
        }

        let task = activeTasks[index]

        do {
            // Get stored relative path
            guard let relativePath = UserDefaults.standard.string(forKey: "download.path.\(taskId)") else {
                throw DownloadError.fileSystemError("Path not found")
            }

            // Move file to final destination
            try fileService.moveFile(from: tempFileUrl, to: relativePath)

            // Download artwork
            var artworkRelativePath: String?
            if let thumb = task.thumb {
                artworkRelativePath = await downloadArtwork(thumb: thumb, task: task)
            }

            // Get file size
            let fileSize = fileService.fileSize(at: relativePath) ?? 0

            // Create completed item
            let completedItem = DownloadedItem(
                id: task.id,
                serverId: task.serverId,
                ratingKey: task.ratingKey,
                type: task.type,
                title: task.title,
                year: task.year,
                summary: nil,
                duration: nil,
                grandparentTitle: task.grandparentTitle,
                grandparentRatingKey: task.grandparentRatingKey,
                parentIndex: task.parentIndex,
                index: task.index,
                videoPath: relativePath,
                artworkPath: artworkRelativePath,
                downloadedAt: Date(),
                fileSize: fileSize
            )

            // Update state
            activeTasks.removeAll { $0.id == taskId }
            downloadedItems.append(completedItem)

            // Save to storage
            storageService.saveQueue(activeTasks)
            storageService.addCompletedDownload(completedItem)

            // Cleanup
            cleanupDownloadState(taskId: taskId)

            // Clear stored path and retry data
            UserDefaults.standard.removeObject(forKey: "download.path.\(taskId)")
            resumeDataStore.removeValue(forKey: taskId)
            lastProgressStore.removeValue(forKey: taskId)
            stuckRetryCount.removeValue(forKey: taskId)

            print("[DownloadManager] Download completed: \(taskId)")

        } catch {
            print("[DownloadManager] Failed to complete download: \(error)")
            activeTasks[index].status = .failed
            activeTasks[index].errorMessage = error.localizedDescription
            storageService.saveQueue(activeTasks)
            cleanupDownloadState(taskId: taskId)
        }

        // Process next in queue
        processQueue()
    }

    private func handleDownloadFailure(taskId: String, error: Error) {
        guard let index = activeTasks.firstIndex(where: { $0.id == taskId }) else { return }

        // Extract resume data from error if available
        let nsError = error as NSError
        if let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
            resumeDataStore[taskId] = resumeData
            print("[DownloadManager] Saved resume data for: \(taskId) (\(resumeData.count) bytes)")
        }

        // Check current progress
        let currentProgress = activeTasks[index].downloadedBytes
        let lastProgress = lastProgressStore[taskId] ?? 0

        // Check if we made progress since last failure
        let madeProgress = currentProgress > lastProgress
        lastProgressStore[taskId] = currentProgress

        if madeProgress {
            // Reset stuck counter since we're making progress
            stuckRetryCount[taskId] = 0
            print("[DownloadManager] Connection lost but made progress (\(formatBytes(currentProgress)) downloaded), retrying immediately: \(taskId)")
        } else {
            // No progress made, increment stuck counter
            let stuckCount = (stuckRetryCount[taskId] ?? 0) + 1
            stuckRetryCount[taskId] = stuckCount

            if stuckCount >= maxStuckRetries {
                // Stuck for too long, give up
                print("[DownloadManager] Download stuck (no progress for \(stuckCount) retries): \(taskId) - \(error)")

                activeTasks[index].status = .failed
                activeTasks[index].errorMessage = "Download stuck. Tap to retry."
                storageService.saveQueue(activeTasks)

                cleanupDownloadState(taskId: taskId)
                resumeDataStore.removeValue(forKey: taskId)
                lastProgressStore.removeValue(forKey: taskId)
                stuckRetryCount.removeValue(forKey: taskId)

                // Process next in queue
                processQueue()
                return
            }

            print("[DownloadManager] Connection lost, no progress made (stuck \(stuckCount)/\(maxStuckRetries)), retrying: \(taskId)")
        }

        // Cleanup and retry immediately
        cleanupDownloadState(taskId: taskId)
        retryDownloadWithResumeData(taskId)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// Retry a download using saved resume data if available
    private func retryDownloadWithResumeData(_ taskId: String) {
        guard let index = activeTasks.firstIndex(where: { $0.id == taskId }) else { return }

        let task = activeTasks[index]

        // Check if we have resume data
        if let resumeData = resumeDataStore[taskId] {
            print("[DownloadManager] Resuming download with saved data: \(taskId)")

            let downloadTask = urlSession.downloadTask(withResumeData: resumeData)
            activeDownloadTasks[taskId] = downloadTask
            taskToGlobalKey[downloadTask.taskIdentifier] = taskId

            // Observe progress
            let observation = downloadTask.progress.observe(
                \Progress.fractionCompleted,
                options: [.new]
            ) { [weak self] (progress: Progress, _) in
                Task { @MainActor [weak self] in
                    self?.handleProgressUpdate(
                        taskId: taskId,
                        progress: progress.fractionCompleted,
                        bytes: progress.completedUnitCount,
                        total: progress.totalUnitCount
                    )
                }
            }
            downloadProgressObservers[taskId] = observation

            downloadTask.resume()
        } else {
            // No resume data, restart from beginning
            print("[DownloadManager] No resume data, restarting download: \(taskId)")
            activeTasks[index].status = .queued
            activeTasks[index].progress = 0
            activeTasks[index].downloadedBytes = 0
            storageService.saveQueue(activeTasks)
            processQueue()
        }
    }

    private func cleanupDownloadState(taskId: String) {
        activeDownloadTasks.removeValue(forKey: taskId)
        downloadProgressObservers[taskId]?.invalidate()
        downloadProgressObservers.removeValue(forKey: taskId)
    }

    // MARK: - Artwork Download

    private func downloadArtwork(thumb: String, task: DownloadTask) async -> String? {
        guard let plexServer = FlixorCore.shared.plexServer,
              let imageUrlString = plexServer.getImageUrl(path: thumb, width: 400),
              let imageUrl = URL(string: imageUrlString) else {
            return nil
        }

        // Compute artwork path
        let artworkRelativePath: String
        if task.type == .movie {
            artworkRelativePath = fileService.movieArtworkPath(title: task.title, year: task.year)
        } else {
            artworkRelativePath = fileService.showArtworkPath(show: task.grandparentTitle ?? "Unknown")
        }

        // Check if already exists
        if fileService.fileExists(at: artworkRelativePath) {
            return artworkRelativePath
        }

        do {
            // Ensure directory exists
            try fileService.ensureDirectoryExists(for: artworkRelativePath)

            // Download artwork data
            var request = URLRequest(url: imageUrl)
            if let token = FlixorCore.shared.getPlexToken() {
                request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
            }

            let (data, _) = try await urlSession.data(for: request)

            // Write to file
            let absoluteUrl = fileService.absolutePath(for: artworkRelativePath)
            try data.write(to: absoluteUrl)

            return artworkRelativePath
        } catch {
            print("[DownloadManager] Failed to download artwork: \(error)")
            return nil
        }
    }
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let taskIdentifier = downloadTask.taskIdentifier

        // CRITICAL: The system will delete the temp file as soon as this method returns.
        // We MUST copy the file SYNCHRONOUSLY before switching to @MainActor.
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        let safeTempUrl = tempDir.appendingPathComponent("flixor_download_\(UUID().uuidString).tmp")

        do {
            // Immediately copy to a safe location before the system deletes it
            try fileManager.copyItem(at: location, to: safeTempUrl)
        } catch {
            print("[DownloadManager] Failed to copy temp file: \(error)")
            Task { @MainActor in
                guard let globalKey = self.taskToGlobalKey[taskIdentifier] else { return }
                self.taskToGlobalKey.removeValue(forKey: taskIdentifier)
                self.handleDownloadFailure(taskId: globalKey, error: error)
            }
            return
        }

        Task { @MainActor in
            guard let globalKey = self.taskToGlobalKey[taskIdentifier] else {
                print("[DownloadManager] Unknown task completed: \(taskIdentifier)")
                try? fileManager.removeItem(at: safeTempUrl)  // Cleanup
                return
            }

            self.taskToGlobalKey.removeValue(forKey: taskIdentifier)
            await self.handleDownloadCompletion(taskId: globalKey, tempFileUrl: safeTempUrl)

            // Cleanup our temp copy after moving
            try? fileManager.removeItem(at: safeTempUrl)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error else { return }

        let taskIdentifier = task.taskIdentifier

        Task { @MainActor in
            guard let globalKey = self.taskToGlobalKey[taskIdentifier] else { return }
            self.taskToGlobalKey.removeValue(forKey: taskIdentifier)
            self.handleDownloadFailure(taskId: globalKey, error: error)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let taskIdentifier = downloadTask.taskIdentifier

        Task { @MainActor in
            guard let globalKey = self.taskToGlobalKey[taskIdentifier] else { return }

            let progress = totalBytesExpectedToWrite > 0
                ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
                : 0

            self.handleProgressUpdate(
                taskId: globalKey,
                progress: progress,
                bytes: totalBytesWritten,
                total: totalBytesExpectedToWrite
            )
        }
    }
}
