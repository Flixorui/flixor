//
//  LogsView.swift
//  FlixorMac
//
//  View for displaying, copying, and clearing app logs
//

import SwiftUI
import AppKit

struct LogsView: View {
    @ObservedObject private var logger = AppLogger.shared
    @State private var showClearConfirmation = false

    private let logColors: [LogLevel: Color] = [
        .debug: .gray,
        .info: .primary,
        .warn: .orange,
        .error: .red
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with count
            HStack {
                Text("\(logger.logCount) \(logger.logCount == 1 ? "entry" : "entries")")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Spacer()

                // Action buttons
                HStack(spacing: 8) {
                    Button(action: copyAllLogs) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                            Text("Copy All")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(logger.logs.isEmpty)

                    Button(action: { showClearConfirmation = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("Clear")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(logger.logs.isEmpty)
                    .tint(.red)
                }
            }

            // Log entries
            SettingsGroupCard {
                if logger.logs.isEmpty {
                    emptyState
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(logger.logs.reversed()) { entry in
                                    logEntryRow(entry)
                                }
                            }
                            .padding(12)
                        }
                        .frame(maxHeight: 400)
                    }
                }
            }

            // Info note
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Logs are stored in memory and will be cleared when the app restarts. Sensitive data like tokens and passwords are automatically redacted.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .alert("Clear Logs", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                logger.clearLogs()
            }
        } message: {
            Text("Are you sure you want to clear all logs?")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 36))
                .foregroundStyle(.quaternary)
            Text("No logs yet")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Enable debug logging to capture detailed logs")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Log Entry Row

    private func logEntryRow(_ entry: LogEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                // Timestamp
                Text(formatTimestamp(entry.timestamp))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)

                // Level badge
                Text(entry.level.uppercased)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(logColors[entry.level] ?? .primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill((logColors[entry.level] ?? .primary).opacity(0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke((logColors[entry.level] ?? .primary).opacity(0.3), lineWidth: 1)
                            )
                    )
            }

            // Message
            Text(entry.message)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(logColors[entry.level] ?? .primary)
                .textSelection(.enabled)

            // Data (if present)
            if let data = entry.data {
                Text(data)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 8)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color.primary.opacity(0.1))
                            .frame(width: 2)
                    }
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Divider()
                .opacity(0.5)
        }
    }

    // MARK: - Actions

    private func copyAllLogs() {
        let exportedLogs = logger.exportLogs()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(exportedLogs, forType: .string)
    }

    // MARK: - Helpers

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}

#if DEBUG
struct LogsView_Previews: PreviewProvider {
    static var previews: some View {
        LogsView()
            .frame(width: 600, height: 500)
            .padding()
    }
}
#endif
