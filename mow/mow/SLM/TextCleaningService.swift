//
//  TextCleaningService.swift
//  mow
//
//  Post-processes raw STT output: remove fillers, disfluencies, hesitation markers (task 6.1).
//  Uses LLM from Hugging Face when loaded (6.2); otherwise rule-based. CoreML optional.
//

import CoreML
import Foundation
import os

/// Thread-safe holder for optional SLM reference (avoids NSLock from async contexts; Swift 6).
private actor TextCleaningSLMHolder {
    weak var slm: SLMLLMService?
    func set(_ value: SLMLLMService?) { slm = value }
    func get() -> SLMLLMService? { slm }
}

/// Service that cleans raw transcription text. Uses LLM (Hugging Face) when loaded, else rule-based.
final class TextCleaningService: @unchecked Sendable {
    private let ruleBasedCleaner = RuleBasedTextCleaner()
    private var coreMLCleaner: CoreMLTextCleaner?
    private let slmHolder = TextCleaningSLMHolder()
    private let lock = NSLock()

    init() {
        loadCoreMLModelIfAvailable()
    }

    /// Set the LLM-based SLM (from ModelManager after load). Use for 6.2 pipeline.
    func setSLMLLMService(_ service: SLMLLMService?) {
        Task { await slmHolder.set(service) }
    }

    /// Clean raw STT output (async): when enabled, LLM if loaded then rule-based, else rule-based only.
    /// When disabled (6.6), returns raw text as-is.
    func clean(rawText: String) async -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        guard TextCleaningSettings.isEnabled else { return trimmed }

        guard let llm = await slmHolder.get(),
              await llm.isReady,
              let cleaned = await llm.clean(rawText: trimmed) else {
            return ruleBasedCleaner.clean(rawText: trimmed)
        }
        return ruleBasedCleaner.clean(rawText: cleaned)
    }

    /// Sync clean: rule-based only (for callers that cannot await).
    func cleanSync(rawText: String) -> String {
        ruleBasedCleaner.clean(rawText: rawText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Attempt to load a CoreML text-cleaning model from ModelStorage.slmModelsURL. No-op if no model found.
    private func loadCoreMLModelIfAvailable() {
        let url = ModelStorage.slmModelsURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        // Look for compiled model (.mlmodelc) or uncompiled (.mlmodel)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        ) else { return }
        let modelURL = contents.first { $0.pathExtension == "mlmodelc" || $0.pathExtension == "mlmodel" }
        guard let modelURL, let cleaner = CoreMLTextCleaner(modelURL: modelURL) else { return }
        lock.lock()
        coreMLCleaner = cleaner
        lock.unlock()
        modelLog.info("SLM CoreML model loaded from \(modelURL.lastPathComponent)")
    }
}

/// Runs a CoreML model for text-to-text cleaning. Model input/output format depends on the chosen model.
/// Returns nil if inference fails or model format is not supported.
final class CoreMLTextCleaner: @unchecked Sendable {
    private var model: MLModel?

    init?(modelURL: URL) {
        let config = MLModelConfiguration()
        config.computeUnits = STTComputePreference.preferredComputeUnits
        do {
            let loaded = try MLModel(contentsOf: modelURL, configuration: config)
            self.model = loaded
        } catch {
            modelLog.error("Failed to load SLM CoreML model: \(error.localizedDescription)")
            return nil
        }
    }

    /// Run the model. Returns cleaned string or nil if not applicable (e.g. model expects different I/O).
    func clean(rawText: String) -> String? {
        guard model != nil else { return nil }
        // Model input/output format is model-specific. Many text models use token IDs or sequences.
        // If the model has a string input/output, we'd use that. For a generic placeholder we return nil
        // so the caller falls back to rule-based. When a specific CoreML disfluency model is integrated,
        // implement the proper input/output handling here.
        return nil
    }
}
