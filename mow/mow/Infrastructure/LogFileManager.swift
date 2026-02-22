//
//  LogFileManager.swift
//  mow
//
//  Persistent log file for transcriptions and errors; used by Logs UI.
//

import Foundation

enum LogFileManager {
    private static let logFileName = "mow.log"
    private static let lock = NSLock()

    /// Log file URL: ~/Library/Application Support/Mow/logs/mow.log (or sandboxed equivalent).
    static var logFileURL: URL {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return fm.temporaryDirectory.appendingPathComponent(logFileName)
        }
        let dir = appSupport.appendingPathComponent("Mow/logs", isDirectory: true)
        return dir.appendingPathComponent(logFileName)
    }

    /// Append a timestamped line to the log file. Thread-safe.
    static func append(_ line: String) {
        let formatted = "\(Self.timestamp()) \(line)\n"
        lock.lock()
        defer { lock.unlock() }
        do {
            let url = logFileURL
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                handle.seekToEndOfFile()
                handle.write(Data(formatted.utf8))
                try handle.close()
            } else {
            try formatted.write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            // Non-fatal; os.log still works
        }
    }

    /// Read entire log file content. Returns empty string if missing or unreadable.
    static func contents() -> String {
        lock.lock()
        defer { lock.unlock() }
        let url = logFileURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            return ""
        }
        return content
    }

    /// Clear the log file (delete and recreate empty). Thread-safe.
    static func clear() {
        lock.lock()
        defer { lock.unlock() }
        let url = logFileURL
        try? FileManager.default.removeItem(at: url)
    }

    /// Size of the log file in bytes, or 0 if missing.
    static func fileSizeBytes() -> Int64 {
        let url = logFileURL
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let num = attrs[.size] as? NSNumber else {
            return 0
        }
        return num.int64Value
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
