//
//  AudioQualityCheck.swift
//  mow
//
//  Edge-case handling for §11.1: poor quality, very short recording.
//  Background noise is not filtered; we pass input through to STT.
//

import Foundation
import os

/// Result of checking captured audio for common issues (design doc §11.1).
enum AudioQualityResult {
    case ok
    case tooShort
    case tooQuiet(rms: Float)

    var userMessage: String? {
        switch self {
        case .ok: return nil
        case .tooShort: return "Recording was too short. Hold the shortcut longer while speaking."
        case .tooQuiet: return "Recording was very quiet. Speak closer to the microphone or check input level."
        }
    }
}

enum AudioQualityCheck {
    /// Minimum duration (seconds) to consider worth processing.
    static let minDurationSeconds: Double = 0.3
    /// RMS below this is considered "too quiet" (normalized float).
    static let minRMSThreshold: Float = 0.008

    /// Check buffer for too-short or too-quiet recording. Call on main optional.
    static func check(samples: [Float], sampleRate: Double = AudioCaptureConstants.sampleRate) -> AudioQualityResult {
        let duration = Double(samples.count) / sampleRate
        if duration < minDurationSeconds {
            return .tooShort
        }
        let rms = Self.computeRMS(samples)
        if rms < minRMSThreshold {
            return .tooQuiet(rms: rms)
        }
        return .ok
    }

    private static func computeRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumSq = samples.reduce(0.0) { $0 + Double($1 * $1) }
        return Float(sqrt(sumSq / Double(samples.count)))
    }
}
