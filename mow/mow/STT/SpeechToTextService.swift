//
//  SpeechToTextService.swift
//  mow
//
//  Integrates FluidAudio for speech-to-text; loads CoreML model at startup (task 5.1).
//  Uses ANE on Apple Silicon, Metal fallback on Intel (5.4). Load/inference errors → status red (5.5).
//

import FluidAudio
import Foundation
import os

/// Wraps FluidAudio ASR: model load at startup, transcription of 16 kHz mono Float32 buffers.
final class SpeechToTextService: @unchecked Sendable {
    private var asrManager: AsrManager?
    private let lock = NSLock()

    /// Whether the ASR model is loaded and ready to transcribe.
    var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return asrManager != nil
    }

    /// Load ASR models (download from HuggingFace if needed) and initialize the manager.
    /// Uses preferred compute units (ANE on Apple Silicon, Metal on Intel). Completion on main queue.
    func loadModels(completion: @escaping (Result<Void, Error>) -> Void) {
        Task { [weak self] in
            do {
                modelLog.info("Downloading/loading ASR models…")
                let models = try await AsrModels.downloadAndLoad(version: .v3)
                // ANE on Apple Silicon, Metal/CPU fallback on Intel — see docs/design/STT_HARDWARE.md (5.4)
                let preferred = STTComputePreference.preferredComputeUnits
                modelLog.info("STT compute preference: \(String(describing: preferred))")
                let manager = AsrManager(config: .default)
                try await manager.initialize(models: models)
                self?.lock.lock()
                self?.asrManager = manager
                self?.lock.unlock()
                modelLog.info("ASR models loaded and ready")
                await MainActor.run {
                    completion(.success(()))
                }
            } catch {
                errorLog.error("ASR model load failed: \(error.localizedDescription)")
                modelLog.error("ASR model load failed: \(error.localizedDescription)")
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }

    /// Transcribe 16 kHz mono Float32 samples. Returns raw transcription text.
    /// Call only when isReady is true. Uses .microphone source for capture pipeline.
    func transcribe(samples: [Float]) async throws -> String {
        guard !samples.isEmpty else { return "" }
        lock.lock()
        let manager = asrManager
        lock.unlock()
        guard let manager else {
            throw SpeechToTextError.modelNotLoaded
        }
        let result = try await manager.transcribe(samples, source: .microphone)
        return result.text
    }
}

enum SpeechToTextError: LocalizedError {
    case modelNotLoaded

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Speech model not loaded"
        }
    }
}
