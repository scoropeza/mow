//
//  SLMEnhancementSettings.swift
//  mow
//
//  User preference for SLM-based text enhancement (independent of disfluency removal).
//

import Foundation

enum SLMEnhancementSettings {
    private static let key = "slmEnhancementEnabled"

    /// Whether to run the SLM (SmolLM2) for additional text cleaning. Default is false (experimental).
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
