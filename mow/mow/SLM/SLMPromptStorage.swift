//
//  SLMPromptStorage.swift
//  mow
//
//  Configurable system prompt for SLM behavior (task 6.4). Persisted in UserDefaults.
//

import Foundation

enum SLMPromptStorage {
    private static let key = "slmSystemPrompt"

    /// Default system prompt used when none is saved. /no_think asks Qwen3 to skip <think> blocks.
    static let defaultPrompt = """
    /no_think
    You are a text cleaner. Remove filler words (um, uh, er, ah, like), disfluencies, repeated words, \
    and hesitation markers from the user's transcript. Output only the cleaned text, nothing else. \
    Do not add punctuation or change the meaning.
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
