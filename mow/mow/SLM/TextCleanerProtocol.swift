//
//  TextCleanerProtocol.swift
//  mow
//
//  Protocol for text cleaning (task 6.1). Implementations: rule-based, or CoreML-based when a model is available.
//

import Foundation

/// Post-processes raw STT output: remove fillers, disfluencies, hesitation markers.
protocol TextCleaner {
    func clean(rawText: String) -> String
}
