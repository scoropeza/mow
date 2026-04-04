//
//  SLMPromptStorage.swift
//  mow
//
//  Configurable system prompt for SLM behavior (task 6.4). Persisted in UserDefaults.
//

import Foundation

enum SLMPromptStorage {
    private static let key = "slmSystemPrompt"

    /// Default system prompt used when none is saved.
    static let defaultPrompt = """
    Remove filler words (um, uh, er, ah, like, you know, basically) and repeated words from the text. \
    Keep all other words exactly as spoken, in the same order. Never rephrase or add words. \
    Output only the cleaned text.
    """

    /// Current system prompt (saved override or default). Main thread safe.
    static var currentPrompt: String {
        get {
            let raw = UserDefaults.standard.string(forKey: key)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let useRaw = raw?.isEmpty == false ? raw : nil
            return useRaw ?? defaultPrompt
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                UserDefaults.standard.removeObject(forKey: key)
            } else {
                UserDefaults.standard.set(trimmed, forKey: key)
            }
        }
    }

    /// Reset to the default prompt.
    static func resetToDefault() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
