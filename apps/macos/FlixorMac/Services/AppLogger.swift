//
//  AppLogger.swift
//  FlixorMac
//
//  Centralized logging system with circular buffer
//  Supports debug, info, warn, error levels with sensitive data redaction
//  Intercepts stdout/stderr to capture all print statements
//

import Foundation
import os.log

// MARK: - Log Types

enum LogLevel: String, CaseIterable {
    case debug, info, warn, error

    var uppercased: String { rawValue.uppercased() }
}

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let message: String
    let data: String?
}

// MARK: - AppLogger

final class AppLogger: ObservableObject {
    static let shared = AppLogger()

    @Published private(set) var logs: [LogEntry] = []
    @Published private(set) var debugEnabled: Bool = false

    private let maxEntries = 1000
    private let queue = DispatchQueue(label: "com.flixor.logger", qos: .utility)
    private var isLogging = false

    // Stdout/stderr interception
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var originalStdout: Int32 = -1
    private var originalStderr: Int32 = -1
    private var isIntercepting = false
    private var stdoutSource: DispatchSourceRead?
    private var stderrSource: DispatchSourceRead?

    // Patterns to redact from logs
    private let sensitivePatterns: [NSRegularExpression] = {
        let patterns = [
            "token[\"\\s:=]+[\"']?[\\w-]+[\"']?",
            "password[\"\\s:=]+[\"']?[\\w-]+[\"']?",
            "apikey[\"\\s:=]+[\"']?[\\w-]+[\"']?",
            "api_key[\"\\s:=]+[\"']?[\\w-]+[\"']?",
            "secret[\"\\s:=]+[\"']?[\\w-]+[\"']?",
            "authorization[\"\\s:=]+[\"']?[\\w-]+[\"']?",
            "bearer\\s+[\\w-]+",
            "X-Plex-Token[\"\\s:=]+[\"']?[\\w-]+[\"']?"
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }
    }()

    private init() {
        // Load debug enabled state from UserDefaults
        debugEnabled = UserDefaults.standard.debugLoggingEnabled

        // Only start intercepting if debug logging was previously enabled
        if debugEnabled {
            startIntercepting()
        }
    }

    // MARK: - Enable/Disable

    func setDebugEnabled(_ enabled: Bool) {
        debugEnabled = enabled
        UserDefaults.standard.debugLoggingEnabled = enabled

        if enabled {
            startIntercepting()
        } else {
            stopIntercepting()
        }

        addEntry(.info, message: "Debug logging \(enabled ? "enabled" : "disabled")")
    }

    // MARK: - Stdout/Stderr Interception using DispatchSource

    private func startIntercepting() {
        guard !isIntercepting else { return }
        isIntercepting = true

        // Save original file descriptors
        originalStdout = dup(STDOUT_FILENO)
        originalStderr = dup(STDERR_FILENO)

        // Set stdout to line-buffered for more reliable capture
        setvbuf(stdout, nil, _IOLBF, 0)
        setvbuf(stderr, nil, _IOLBF, 0)

        // Create pipes
        stdoutPipe = Pipe()
        stderrPipe = Pipe()

        guard let stdoutPipe = stdoutPipe, let stderrPipe = stderrPipe else { return }

        // Redirect stdout and stderr
        dup2(stdoutPipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        dup2(stderrPipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

        // Use DispatchSource for more reliable reading
        setupDispatchSource(for: stdoutPipe, isStderr: false)
        setupDispatchSource(for: stderrPipe, isStderr: true)
    }

    private func setupDispatchSource(for pipe: Pipe, isStderr: Bool) {
        let fd = pipe.fileHandleForReading.fileDescriptor
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)

        source.setEventHandler { [weak self] in
            guard let self = self else { return }

            let handle = pipe.fileHandleForReading
            let data = handle.availableData

            guard !data.isEmpty else { return }

            // Write to original descriptor so it still appears in Xcode console
            let originalFd = isStderr ? self.originalStderr : self.originalStdout
            if originalFd >= 0 {
                _ = data.withUnsafeBytes { ptr in
                    write(originalFd, ptr.baseAddress, data.count)
                }
            }

            // Capture the output
            if let output = String(data: data, encoding: .utf8) {
                self.captureOutput(output, isStderr: isStderr)
            }
        }

        source.setCancelHandler {
            // Cleanup when cancelled
        }

        source.resume()

        if isStderr {
            stderrSource = source
        } else {
            stdoutSource = source
        }
    }

    private func captureOutput(_ output: String, isStderr: Bool) {
        // Split by newlines and process each line
        let lines = output.components(separatedBy: .newlines)
            .filter { !$0.isEmpty }

        for line in lines {
            // Skip our own formatted log output to prevent loops
            if line.hasPrefix("[DEBUG]") || line.hasPrefix("[INFO]") ||
               line.hasPrefix("[WARN]") || line.hasPrefix("[ERROR]") {
                continue
            }

            // Determine log level based on content
            let level: LogLevel
            if isStderr {
                level = .error
            } else if line.contains("error") || line.contains("Error") || line.contains("❌") {
                level = .error
            } else if line.contains("warning") || line.contains("Warning") || line.contains("⚠️") {
                level = .warn
            } else if line.contains("✅") || line.contains("[INFO]") {
                level = .info
            } else {
                level = .debug
            }

            // Only store debug level if debug logging is enabled
            if level == .debug && !debugEnabled {
                continue
            }

            addEntry(level, message: line)
        }
    }

    private func stopIntercepting() {
        guard isIntercepting else { return }
        isIntercepting = false

        // Cancel dispatch sources
        stdoutSource?.cancel()
        stderrSource?.cancel()
        stdoutSource = nil
        stderrSource = nil

        // Restore original file descriptors
        if originalStdout >= 0 {
            dup2(originalStdout, STDOUT_FILENO)
            close(originalStdout)
            originalStdout = -1
        }

        if originalStderr >= 0 {
            dup2(originalStderr, STDERR_FILENO)
            close(originalStderr)
            originalStderr = -1
        }

        // Close pipes
        try? stdoutPipe?.fileHandleForWriting.close()
        try? stderrPipe?.fileHandleForWriting.close()
        stdoutPipe = nil
        stderrPipe = nil
    }

    // MARK: - Logging Methods

    func debug(_ message: String, data: Any? = nil) {
        guard debugEnabled else { return }
        addEntry(.debug, message: message, data: data)
        writeToOriginal("[DEBUG] \(message)\n", isStderr: false)
    }

    func info(_ message: String, data: Any? = nil) {
        addEntry(.info, message: message, data: data)
        writeToOriginal("[INFO] \(message)\n", isStderr: false)
    }

    func warn(_ message: String, data: Any? = nil) {
        addEntry(.warn, message: message, data: data)
        writeToOriginal("[WARN] \(message)\n", isStderr: false)
    }

    func error(_ message: String, data: Any? = nil) {
        addEntry(.error, message: message, data: data)
        writeToOriginal("[ERROR] \(message)\n", isStderr: true)
    }

    private func writeToOriginal(_ message: String, isStderr: Bool) {
        let fd = isStderr ? originalStderr : originalStdout
        if fd >= 0 {
            message.withCString { ptr in
                _ = write(fd, ptr, strlen(ptr))
            }
        }
    }

    // MARK: - Entry Management

    private func addEntry(_ level: LogLevel, message: String, data: Any? = nil) {
        guard !isLogging else { return }
        isLogging = true
        defer { isLogging = false }

        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            message: redact(message),
            data: stringifyData(data)
        )

        DispatchQueue.main.async {
            self.logs.append(entry)
            if self.logs.count > self.maxEntries {
                self.logs.removeFirst()
            }
        }
    }

    func clearLogs() {
        DispatchQueue.main.async {
            self.logs.removeAll()
        }
    }

    func getLogs() -> [LogEntry] {
        return logs
    }

    var logCount: Int {
        return logs.count
    }

    // MARK: - Export

    func exportLogs() -> String {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let lines = logs.map { entry in
            let time = dateFormatter.string(from: entry.timestamp)
            let level = entry.level.uppercased.padding(toLength: 5, withPad: " ", startingAt: 0)
            var line = "[\(time)] \(level) \(entry.message)"
            if let data = entry.data {
                line += "\n  Data: \(data)"
            }
            return line
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Redaction

    private func redact(_ text: String) -> String {
        var result = text
        for pattern in sensitivePatterns {
            let range = NSRange(result.startIndex..., in: result)
            result = pattern.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "[REDACTED]")
        }
        return result
    }

    private func stringifyData(_ data: Any?) -> String? {
        guard let data = data else { return nil }

        if let string = data as? String {
            return redact(string)
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: data, options: .prettyPrinted)
            if let string = String(data: jsonData, encoding: .utf8) {
                return redact(string)
            }
        } catch {}

        return redact(String(describing: data))
    }

    deinit {
        stopIntercepting()
    }
}

// MARK: - Global Logging Functions

func logDebug(_ message: String, data: Any? = nil) {
    AppLogger.shared.debug(message, data: data)
}

func logInfo(_ message: String, data: Any? = nil) {
    AppLogger.shared.info(message, data: data)
}

func logWarn(_ message: String, data: Any? = nil) {
    AppLogger.shared.warn(message, data: data)
}

func logError(_ message: String, data: Any? = nil) {
    AppLogger.shared.error(message, data: data)
}
