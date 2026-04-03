//
//  DictationLatencySettings.swift
//  mow
//
//  Developer flag to show dictation latency in the menu bar after each transcription.
//

import Foundation

enum DictationLatencySettings {
    private static let key = "showDictationLatency"

    /// When true, the menu bar briefly shows total latency (e.g. "✓ 1.2s") after each dictation.
    /// Default is false — intended for developer use during performance tuning.
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
