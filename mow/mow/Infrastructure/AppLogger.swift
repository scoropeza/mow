//
//  AppLogger.swift
//  mow
//
//  Central logging and error reporting for status (red) and debugging.
//

import Foundation
import os.log

/// Subsystem for Mów logs; used by OSLog.
private let subsystem = Bundle.main.bundleIdentifier ?? "com.daedalus-labs.mow"

/// App-wide logger for general and debug messages.
let appLog = Logger(subsystem: subsystem, category: "app")

/// Logger for model loading, download, and inference.
let modelLog = Logger(subsystem: subsystem, category: "model")

/// Logger for audio capture and pipeline.
let audioLog = Logger(subsystem: subsystem, category: "audio")

/// Logger for errors that should set status to red and optionally be shown to the user.
let errorLog = Logger(subsystem: subsystem, category: "error")

/// Last error message set by the app; used for "View Logs" / status red.
/// Access from main thread only.
enum AppErrorState {
    private(set) static var lastMessage: String?
    private(set) static var lastTimestamp: Date?

    static func set(_ message: String) {
        lastMessage = message
        lastTimestamp = Date()
        errorLog.fault("\(message)")
        LogFileManager.append("[error] \(message)")
    }

    static func clear() {
        lastMessage = nil
        lastTimestamp = nil
    }
}

/// Last successful transcription; shown in Logs window so the user can see the result.
/// Access from main thread only.
enum AppTranscriptionState {
    private(set) static var lastText: String?
    private(set) static var lastTimestamp: Date?

    static func set(_ text: String) {
        lastText = text
        lastTimestamp = Date()
        modelLog.info("Transcription: \(text)")
        LogFileManager.append("[transcription] \(text)")
    }

    static func clear() {
        lastText = nil
        lastTimestamp = nil
    }
}
