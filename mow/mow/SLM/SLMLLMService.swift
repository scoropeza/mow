//
//  SLMLLMService.swift
//  mow
//
//  SLM using LLM.swift: loads a small model from Hugging Face for text cleaning (task 6.2).
//  Uses configurable system prompt (6.4). Reports load/run errors (6.5).
//

import Foundation
import LLM
import os

/// Hugging Face model used for text cleaning. Small model for low latency.
private let slmModelID = "unsloth/Qwen3-0.6B-GGUF"

/// Thread-safe state for SLM (avoids NSLock from async contexts; Swift 6).
private actor SLMLLMState {
    var llm: LLM?
    var onInferenceError: (() -> Void)?

    func setLLM(_ value: LLM?) { llm = value }
    func setOnInferenceError(_ value: (() -> Void)?) { onInferenceError = value }
    func getLLM() -> LLM? { llm }
}

/// SLM backed by LLM.swift: loads from Hugging Face, cleans raw STT output via LLM completion.
final class SLMLLMService: @unchecked Sendable {
    private let state = SLMLLMState()

    var isReady: Bool {
        get async { await state.getLLM() != nil }
    }

    /// Set callback when inference fails (6.5). Called on main queue.
    func setOnInferenceError(_ handler: (() -> Void)?) {
        Task { await state.setOnInferenceError(handler) }
    }

    /// Load the model from Hugging Face (downloads if not present). Uses systemPrompt (6.4). Call once at startup.
    func loadFromHuggingFace(
        systemPrompt: String,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        Task {
            do {
                let prompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? SLMPromptStorage.defaultPrompt
                    : systemPrompt
                let model = HuggingFaceModel(slmModelID, .Q4_K_M, template: .chatML(prompt))
                guard let loaded = try await LLM(
                    from: model,
                    to: ModelStorage.slmModelsURL,
                    updateProgress: { frac in Task { @MainActor in progress(frac) } }
                ) else {
                    throw NSError(
                        domain: "SLMLLMService",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "LLM init returned nil"]
                    )
                }
                await state.setLLM(loaded)
                modelLog.info("SLM (LLM.swift) loaded from Hugging Face: \(slmModelID)")
                await MainActor.run { completion(.success(())) }
            } catch {
                modelLog.error("SLM load failed: \(error.localizedDescription)")
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }

    /// Clean raw transcript using the LLM. Returns cleaned text or nil if not ready.
    /// Inference errors reported via callback when LLM API throws (6.5).
    func clean(rawText: String) async -> String? {
        guard let model = await state.getLLM() else { return nil }
        let trimmed = rawText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        let processed = model.preprocess(trimmed, [], .none)
        let result = await model.getCompletion(from: processed)
        return result.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
}
