//
//  DisfluencySettings.swift
//  mow
//
//  User preference for ModernBERT disfluency removal (independent of SLM text cleaning).
//

import Foundation

enum DisfluencySettings {
    private static let key = "disfluencyRemovalEnabled"

    /// Whether to run the ModernBERT disfluency classifier on STT output. Default is true.
    static var isEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: key) != nil else { return true }
            return UserDefaults.standard.bool(forKey: key)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
        }
    }
}
