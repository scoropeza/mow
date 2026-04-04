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

/// Service that cleans raw transcription text. Pipeline:
/// 1. Disfluency classifier (ModernBERT, if enabled) — tags and removes fillers/repetitions
/// 2. SLM enhancement (SmolLM2, if enabled) — context-aware cleaning
/// 3. Rule-based cleaner — catches remaining fillers and normalizes whitespace
final class TextCleaningService: @unchecked Sendable {
    private let ruleBasedCleaner = RuleBasedTextCleaner()
    private var coreMLCleaner: CoreMLTextCleaner?
    private let slmHolder = TextCleaningSLMHolder()
    private let disfluencyClassifier = DisfluencyClassifier()
    private let lock = NSLock()

    init() {
        loadCoreMLModelIfAvailable()
    }

    /// Load the disfluency classifier model. Call once at startup.
    func loadDisfluencyClassifier() async {
        do {
            try await disfluencyClassifier.load()
            modelLog.info("Disfluency classifier ready")
        } catch {
            modelLog.warning("Disfluency classifier failed to load: \(error.localizedDescription)")
        }
    }

    /// Set the LLM-based SLM (from ModelManager after load). Use for 6.2 pipeline.
    func setSLMLLMService(_ service: SLMLLMService?) {
        Task { await slmHolder.set(service) }
    }

    /// Clean raw STT output (async). Pipeline: disfluency classifier → SLM → rule-based.
    /// Each step runs only if its toggle is enabled in Settings.
    func clean(rawText: String) async -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        guard TextCleaningSettings.isEnabled else { return trimmed }

        var text = trimmed

        // Step 1: Disfluency classifier (deterministic, ~10ms)
        if DisfluencySettings.isEnabled, disfluencyClassifier.isReady {
            do {
                text = try disfluencyClassifier.clean(text: text)
            } catch {
                modelLog.warning("Disfluency classifier error: \(error.localizedDescription)")
            }
        }

        // Step 2: SLM enhancement (optional, ~500ms)
        if SLMEnhancementSettings.isEnabled,
           let llm = await slmHolder.get(),
           await llm.isReady,
           let slmCleaned = await llm.clean(rawText: text) {
            text = slmCleaned
        }

        // Step 3: Rule-based cleanup (always, <5ms)
        return ruleBasedCleaner.clean(rawText: text)
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
