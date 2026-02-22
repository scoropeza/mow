//
//  LogsView.swift
//  mow
//
//  Logs window: link to log file, file size, and full persisted log content.
//

import SwiftUI
import AppKit

struct LogsView: View {
    @State private var logContent: String = ""
    @State private var logFileSizeBytes: Int64 = 0
    @State private var lastError: String?
    @State private var lastErrorTime: Date?

    var body: some View {
        Form {
            if let msg = lastError {
                Section("Last error") {
                    Text(msg)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let time = lastErrorTime {
                        Text(time, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section("Log file") {
                Button(action: openLogFile) {
                    HStack {
                        Text("Open log file:")
                            .foregroundStyle(.secondary)
                        Text(LogFileManager.logFileURL.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.blue)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                Text("Size: \(ByteCountFormatter.string(fromByteCount: logFileSizeBytes, countStyle: .file))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Log content") {
                TextEditor(text: .constant(logContent))
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 200, maxHeight: 400)
                    .disabled(true)
                HStack {
                    Button("Refresh") {
                        refreshLogContent()
                        lastError = AppErrorState.lastMessage
                        lastErrorTime = AppErrorState.lastTimestamp
                    }
                    Button("Clear log", role: .destructive) {
                        LogFileManager.clear()
                        AppErrorState.clear()
                        lastError = nil
                        lastErrorTime = nil
                        refreshLogContent()
                    }
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(logContent, forType: .string)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 320)
        .onAppear {
            refreshLogContent()
            lastError = AppErrorState.lastMessage
            lastErrorTime = AppErrorState.lastTimestamp
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            lastError = AppErrorState.lastMessage
            lastErrorTime = AppErrorState.lastTimestamp
        }
    }

    private func refreshLogContent() {
        logContent = LogFileManager.contents()
        logFileSizeBytes = LogFileManager.fileSizeBytes()
    }

    private func openLogFile() {
        NSWorkspace.shared.open(LogFileManager.logFileURL)
    }
}
