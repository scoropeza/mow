//
//  ModelManagementView.swift
//  mow
//
//  Model management (7.4–7.6): list STT/SLM models, metadata, reload, clear cache.
//

import SwiftUI
import AppKit

struct ModelManagementView: View {
    var modelManager: ModelManager

    @State private var sttCacheSizeBytes: Int64 = 0
    @State private var slmItems: [ModelStorage.CachedSLMItem] = []
    @State private var slmReloading = false
    @State private var slmReloadError: String?
    @State private var showClearSLMConfirmation = false
    @State private var clearSLMError: String?

    var body: some View {
        Form {
            Section("Speech-to-Text") {
                HStack {
                    Label("FluidAudio ASR v3", systemImage: "waveform")
                    Spacer()
                    if modelManager.isSTTReady {
                        Text("Loaded")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not loaded")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                cacheLocationButton(url: ModelStorage.fluidAudioModelsURL)
                Text("Cache: \(ByteCountFormatter.string(fromByteCount: sttCacheSizeBytes, countStyle: .file))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Text cleaning (SLM)") {
                cacheLocationButton(url: ModelStorage.slmModelsURL)
                Text("Current model: \(slmItems.isEmpty ? "None" : ModelStorage.defaultSLMModelID)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !slmItems.isEmpty {
                    ForEach(slmItems) { item in
                        HStack {
                            if let url = huggingFaceURL(for: item.name) {
                                Link(destination: url) {
                                    Text(item.name)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            } else {
                                Text(item.name)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Text(item.sizeFormatted)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("No SLM files in cache")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let err = slmReloadError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                HStack {
                    Button(slmReloading ? "Loading…" : "Download / Reload SLM") {
                        triggerSLMReload()
                    }
                    .disabled(slmReloading)
                    Button("Clear SLM cache", role: .destructive) {
                        showClearSLMConfirmation = true
                    }
                }
                if let err = clearSLMError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Text("Total cache: " + ByteCountFormatter.string(
                    fromByteCount: ModelStorage.totalCacheSizeBytes(),
                    countStyle: .file
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 320, minHeight: 280)
        .onAppear { refreshCacheInfo() }
        .alert("Clear SLM cache?", isPresented: $showClearSLMConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { clearSLMCache() }
        } message: {
            Text("Removes downloaded text-cleaning model files. They will be re-downloaded when needed.")
        }
    }

    private func refreshCacheInfo() {
        sttCacheSizeBytes = ModelStorage.directorySizeBytes(at: ModelStorage.fluidAudioModelsURL)
        slmItems = ModelStorage.listSLMCache()
        slmReloadError = nil
        clearSLMError = nil
    }

    private func triggerSLMReload() {
        slmReloading = true
        slmReloadError = nil
        let onComplete: (Result<Void, Error>) -> Void = { result in
            slmReloading = false
            switch result {
            case .success:
                refreshCacheInfo()
            case .failure(let error):
                slmReloadError = error.localizedDescription
            }
        }
        modelManager.reloadSLM(progress: { _ in }, onFailure: { _ in }, completion: onComplete)
    }

    private func clearSLMCache() {
        do {
            try ModelStorage.clearSLMCache()
            refreshCacheInfo()
        } catch {
            clearSLMError = error.localizedDescription
        }
    }

    private func cacheLocationButton(url: URL) -> some View {
        Button(
            action: { NSWorkspace.shared.open(url) },
            label: {
                HStack {
                    Text("Cache location:")
                        .foregroundStyle(.secondary)
                    Text(url.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.blue)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        )
        .buttonStyle(.plain)
    }

    /// Hugging Face model repo page URL. Cache names are often filenames; we link to the repo page, not the file.
    private func huggingFaceURL(for cacheName: String) -> URL? {
        // Default SLM is unsloth/SmolLM2-1.7B-Instruct-GGUF — link to the model page, not a file path.
        if cacheName.contains("SmolLM2") || cacheName.contains("unsloth") {
            return URL(string: "https://huggingface.co/unsloth/SmolLM2-1.7B-Instruct-GGUF")
        }
        // Other models: try org--model style folder names.
        let modelId = cacheName.replacingOccurrences(of: "--", with: "/")
        guard !modelId.contains(".") else { return nil }
        return URL(string: "https://huggingface.co/\(modelId)")
    }
}
