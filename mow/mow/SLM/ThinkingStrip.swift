//
//  ThinkingStrip.swift
//  mow
//
//  Strips model reasoning blocks (think tags) from LLM output so only the final answer is shown to the user.
//

import Foundation

enum ThinkingStrip {
    private static let thinkOpen = "<think>"
    private static let thinkClose = "</think>"

    /// Returns only the final answer: removes any <think>...</think> block (case-insensitive) and trims.
    /// Logging should use the full string; injection/clipboard should use this.
    static func finalAnswer(from combined: String) -> String {
        var text = combined.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }
        let options: String.CompareOptions = [.caseInsensitive]
        while let startRange = text.range(of: thinkOpen, options: options) {
            let searchStart = startRange.upperBound
            guard searchStart < text.endIndex else { break }
            let searchRange = searchStart..<text.endIndex
            if let endRange = text.range(of: thinkClose, options: options, range: searchRange) {
                text.removeSubrange(startRange.lowerBound..<endRange.upperBound)
            } else {
                // Unclosed <think>: remove from <think> to end
                text.removeSubrange(startRange.lowerBound..<text.endIndex)
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }
}
