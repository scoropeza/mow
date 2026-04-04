//
//  DisfluencyClassifier.swift
//  mow
//
//  ModernBERT-based token classifier for disfluency removal.
//  Tags each token as O (keep), FP (filled pause), RP (repetition), RV (revision), PW (partial word).
//  Uses ONNX Runtime for inference and HuggingFace Tokenizers for text processing.
//

import Foundation
import OnnxRuntimeBindings
import Tokenizers
import os

/// Labels produced by the disfluency classifier.
enum DisfluencyLabel: Int {
    case fluent = 0        // O — keep
    case filledPause = 1   // FP — um, uh, er
    case repetition = 2    // RP — repeated word
    case revision = 3      // RV — self-correction reparandum
    case partialWord = 4   // PW — incomplete word

    var shouldRemove: Bool { self != .fluent }
}

/// On-device disfluency detection using a ModernBERT token classifier (ONNX Runtime).
final class DisfluencyClassifier: @unchecked Sendable {
    private var session: ORTSession?
    private var tokenizer: Tokenizer?
    private let lock = NSLock()
    private let maxLength = 128

    private static let log = Logger(subsystem: "mow", category: "DisfluencyClassifier")

    /// Load model and tokenizer from app bundle. Call once at startup.
    func load() async throws {
        guard let modelURL = Bundle.main.url(forResource: "DisfluencyClassifier", withExtension: "onnx") else {
            throw DisfluencyError.modelNotFound
        }

        Self.log.info("Loading disfluency classifier...")

        let env = try ORTEnv(loggingLevel: .warning)
        let opts = try ORTSessionOptions()
        try opts.setGraphOptimizationLevel(.all)
        let loadedSession = try ORTSession(env: env, modelPath: modelURL.path, sessionOptions: opts)

        // Load tokenizer — files are in the bundle's Resources root
        guard let resourceDir = Bundle.main.resourceURL else {
            throw DisfluencyError.tokenizerNotFound
        }
        let loadedTokenizer = try await AutoTokenizer.from(modelFolder: resourceDir)

        lock.lock()
        session = loadedSession
        tokenizer = loadedTokenizer
        lock.unlock()

        Self.log.info("Disfluency classifier loaded")
    }

    var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return session != nil && tokenizer != nil
    }

    /// Remove disfluencies from the input text. Returns cleaned text.
    func clean(text: String) throws -> String {
        lock.lock()
        let sess = session
        let tok = tokenizer
        lock.unlock()

        guard let sess, let tok else { throw DisfluencyError.notLoaded }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        // Tokenize
        let tokenIds = tok.encode(text: trimmed)
        let attentionMask = [Int](repeating: 1, count: tokenIds.count)

        // Pad/truncate to maxLength
        let paddedIds = padOrTruncate(tokenIds.map { Int64($0) }, padValue: 0)
        let paddedMask = padOrTruncate(attentionMask.map { Int64($0) }, padValue: 0)

        // Create ORT tensors
        let shape: [NSNumber] = [1, NSNumber(value: maxLength)]
        let idsTensor = try ORTValue(
            tensorData: NSMutableData(data: Data(bytes: paddedIds, count: paddedIds.count * 8)),
            elementType: .int64,
            shape: shape
        )
        let maskTensor = try ORTValue(
            tensorData: NSMutableData(data: Data(bytes: paddedMask, count: paddedMask.count * 8)),
            elementType: .int64,
            shape: shape
        )

        // Run inference
        let outputs = try sess.run(
            withInputs: ["input_ids": idsTensor, "attention_mask": maskTensor],
            outputNames: Set(["logits"]),
            runOptions: nil
        )
        guard let logitsValue = outputs["logits"] else { throw DisfluencyError.noOutput }

        // Parse logits to labels
        let logitsData = try logitsValue.tensorData() as Data
        let labels = parseLogits(logitsData, tokenCount: min(tokenIds.count, maxLength))

        // Map token labels back to words
        let tokens = tokenIds.prefix(maxLength).map { tok.decode(tokens: [$0]) }
        return reconstructCleanText(tokens: tokens, labels: labels, originalText: trimmed)
    }

    // MARK: - Private

    private func padOrTruncate(_ array: [Int64], padValue: Int64) -> [Int64] {
        if array.count >= maxLength { return Array(array.prefix(maxLength)) }
        return array + Array(repeating: padValue, count: maxLength - array.count)
    }

    private func parseLogits(_ data: Data, tokenCount: Int) -> [DisfluencyLabel] {
        let numClasses = 5
        let floatCount = data.count / MemoryLayout<Float>.stride
        var floats = [Float](repeating: 0, count: floatCount)
        _ = floats.withUnsafeMutableBytes { data.copyBytes(to: $0) }

        var labels: [DisfluencyLabel] = []
        for i in 0..<min(tokenCount, maxLength) {
            let offset = i * numClasses
            guard offset + numClasses <= floats.count else { break }
            let scores = floats[offset..<(offset + numClasses)]
            let best = scores.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
            labels.append(DisfluencyLabel(rawValue: best) ?? .fluent)
        }
        return labels
    }

    /// Map subtoken labels back to original words.
    /// A word is removed if ANY of its subtokens is tagged as disfluent.
    private func reconstructCleanText(tokens: [String], labels: [DisfluencyLabel], originalText: String) -> String {
        let words = originalText.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard !words.isEmpty else { return originalText }

        // Build word-level labels from subtoken labels.
        // Tokens with "Ġ" prefix (or first non-special) start a new word.
        var wordLabels: [DisfluencyLabel] = []
        var currentLabel: DisfluencyLabel = .fluent
        var wordIdx = -1

        for (i, token) in tokens.enumerated() {
            guard i < labels.count else { break }
            // Skip special tokens
            let t = token.trimmingCharacters(in: .whitespaces)
            if t == "[CLS]" || t == "[SEP]" || t == "[PAD]"
                || t == "<s>" || t == "</s>" || t == "<pad>" || t.isEmpty {
                continue
            }

            let isWordStart = t.hasPrefix("Ġ") || t.hasPrefix("▁") || wordIdx == -1

            if isWordStart {
                if wordIdx >= 0 { wordLabels.append(currentLabel) }
                wordIdx += 1
                currentLabel = labels[i]
            } else if labels[i].shouldRemove {
                currentLabel = labels[i]
            }
        }
        if wordIdx >= 0 { wordLabels.append(currentLabel) }

        // Keep only fluent words
        var result: [String] = []
        for (idx, word) in words.enumerated() {
            if idx < wordLabels.count {
                if !wordLabels[idx].shouldRemove { result.append(word) }
            } else {
                result.append(word)
            }
        }
        return result.joined(separator: " ")
    }
}

enum DisfluencyError: LocalizedError {
    case modelNotFound
    case tokenizerNotFound
    case notLoaded
    case noOutput

    var errorDescription: String? {
        switch self {
        case .modelNotFound: return "Disfluency model not found in app bundle"
        case .tokenizerNotFound: return "Disfluency tokenizer not found in app bundle"
        case .notLoaded: return "Disfluency classifier not loaded"
        case .noOutput: return "Disfluency classifier produced no output"
        }
    }
}
