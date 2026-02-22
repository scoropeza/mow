//
//  ModelManager.swift
//  mow
//
//  Loads STT and SLM at launch (tasks 5.2, 6.2). STT from FluidAudio; SLM from Hugging Face via LLM.swift.
//

import Foundation
import os

/// Owns STT and SLM loading at launch. Eager load so models are in memory before recording.
final class ModelManager {
    private(set) var sttService = SpeechToTextService()
    private(set) var textCleaningService = TextCleaningService()
    private(set) var slmLLMService = SLMLLMService()

    /// Load STT and SLM at launch. STT required; SLM from Hugging Face (downloads if not present).
    /// Completion on main queue.
    /// - Parameters:
    ///   - onSLMLoadFailure: Called when SLM fails to load (6.5); app can set status red.
    ///   - onSLMInferenceError: Set on SLM service; called when text-cleaning inference fails at runtime (6.5).
    func loadModelsAtLaunch(
        progress: @escaping (String) -> Void = { _ in },
        onSLMLoadFailure: ((Error) -> Void)? = nil,
        onSLMInferenceError: (() -> Void)? = nil,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        do {
            try ModelStorage.createDirectoriesIfNeeded()
        } catch {
            completion(.failure(error))
            return
        }

        progress("Loading speech model…")
        sttService.loadModels { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                completion(.failure(error))
                return
            case .success:
                progress("Loading text cleaning model…")
                self.slmLLMService.setOnInferenceError(onSLMInferenceError)
                self.slmLLMService.loadFromHuggingFace(
                    systemPrompt: SLMPromptStorage.currentPrompt,
                    progress: { _ in },
                    completion: { [weak self] slmResult in
                        guard let self else { return }
                        switch slmResult {
                        case .success:
                            self.textCleaningService.setSLMLLMService(self.slmLLMService)
                            modelLog.info("SLM (LLM.swift) ready for text cleaning")
                        case .failure(let error):
                            modelLog.warning(
                                "SLM load failed, using rule-based cleaning: \(error.localizedDescription)"
                            )
                            onSLMLoadFailure?(error)
                        }
                        completion(.success(()))
                    }
                )
            }
        }
    }

    /// Whether the STT model is loaded and ready (for recording/transcription).
    var isSTTReady: Bool {
        sttService.isReady
    }

    /// Reload the SLM (re-download if needed, then load). Use from Model Management UI (7.5). Completion on main queue.
    func reloadSLM(
        progress: @escaping (Double) -> Void = { _ in },
        onFailure: ((Error) -> Void)? = nil,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        slmLLMService.loadFromHuggingFace(
            systemPrompt: SLMPromptStorage.currentPrompt,
            progress: progress,
            completion: { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    self.textCleaningService.setSLMLLMService(self.slmLLMService)
                    modelLog.info("SLM reloaded for text cleaning")
                    completion(.success(()))
                case .failure(let error):
                    onFailure?(error)
                    completion(.failure(error))
                }
            }
        )
    }
}
