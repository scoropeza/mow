//
//  RuleBasedTextCleaner.swift
//  mow
//
//  Removes fillers, disfluencies, and hesitation markers from raw STT output (task 6.1).
//  Used when no CoreML SLM model is loaded; can run alongside or after a CoreML cleaner.
//

import Foundation

/// Rule-based text cleaner: remove common fillers, repeated words, normalize spaces.
struct RuleBasedTextCleaner: TextCleaner {
    func clean(rawText: String) -> String {
        var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }

        // Remove filler phrases (whole words, case-insensitive). Order matters for multi-word.
        let fillerPhrases = [
            "you know", "i mean", "kind of", "sort of", "you see",
            "let me see", "let's see", "i think", "i guess", "i suppose"
        ]
        for phrase in fillerPhrases {
            text = text.replacingOccurrences(
                of: "\\b\(phrase)\\b",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        // Remove standalone filler words (word boundaries). Omit "like" to avoid stripping from "I like it".
        let fillerWords = [
            "um", "uh", "er", "ah", "hmm", "hm", "eh", "oh",
            "actually", "basically", "literally", "right"
        ]
        for word in fillerWords {
            text = text.replacingOccurrences(
                of: "\\b\(word)\\b",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        // Remove repeated words (e.g. "the the" -> "the")
        text = collapseRepeatedWords(in: text)

        // Normalize whitespace: collapse multiple spaces/newlines to one space, trim
        text = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func collapseRepeatedWords(in text: String) -> String {
        let words = text.components(separatedBy: .whitespaces)
        guard words.count > 1 else { return text }
        var result: [String] = []
        var previous = ""
        for word in words {
            if word.caseInsensitiveCompare(previous) == .orderedSame {
                continue
            }
            result.append(word)
            previous = word
        }
        return result.joined(separator: " ")
    }
}
