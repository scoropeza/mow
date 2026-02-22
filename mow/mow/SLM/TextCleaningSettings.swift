//
//  TextCleaningSettings.swift
//  mow
//
//  User preference for text cleaning (task 6.6). When disabled, STT output is used as-is.
//

import Foundation

enum TextCleaningSettings {
    private static let enabledKey = "textCleaningEnabled"

    /// Whether to run SLM/rule-based cleaning on STT output. Default is false (disabled).
    static var isEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: enabledKey) != nil else { return false }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
        }
    }
}
