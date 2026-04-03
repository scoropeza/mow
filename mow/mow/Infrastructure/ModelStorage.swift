//
//  ModelStorage.swift
//  mow
//
//  Local model storage for speech-to-text and SLM models.
//  Uses ~/Library/Caches/ (or sandboxed Caches) per DESIGN.MD.
//

import Foundation

/// Provides URLs and paths for storing and loading STT and SLM models.
/// Models are cached for faster subsequent loads.
enum ModelStorage {
    private static let subdirectoryName = "Mow"
    private static let sttSubdirectory = "STT"
    private static let slmSubdirectory = "SLM"

    /// Root directory for all Mów cached data (models, etc.).
    /// Resolves to `~/Library/Caches/Mow` (or the app’s sandboxed Caches equivalent).
    static var rootURL: URL {
        guard let caches = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else {
            fatalError("ModelStorage: Unable to resolve caches directory")
        }
        return caches.appendingPathComponent(subdirectoryName, isDirectory: true)
    }

    /// Directory for speech-to-text (FluidAudio/CoreML) models.
    /// May be unused if FluidAudio uses its own cache.
    static var sttModelsURL: URL {
        rootURL.appendingPathComponent(sttSubdirectory, isDirectory: true)
    }

    /// Where FluidAudio stores downloaded ASR models. Use for STT cache size in Model Management.
    /// See: https://github.com/FluidInference/FluidAudio
    static var fluidAudioModelsURL: URL {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return rootURL.appendingPathComponent("STT", isDirectory: true)
        }
        return appSupport.appendingPathComponent("FluidAudio/Models", isDirectory: true)
    }

    /// Directory for text-cleaning SLM (CoreML) models.
    static var slmModelsURL: URL {
        rootURL.appendingPathComponent(slmSubdirectory, isDirectory: true)
    }

    /// Default SLM model ID used by the app (for display in Model Management). Matches SLMLLMService.
    static let defaultSLMModelID = "unsloth/SmolLM2-1.7B-Instruct-GGUF"

    /// Ensures the root and model subdirectories exist. Call at startup before downloading or loading models.
    static func createDirectoriesIfNeeded() throws {
        let fm = FileManager.default
        for url in [rootURL, sttModelsURL, slmModelsURL] {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    // MARK: - Cache listing and management (7.4, 7.6)

    /// Item in the SLM cache: display name and size in bytes.
    struct CachedSLMItem: Identifiable {
        let id: String
        let name: String
        let sizeBytes: Int64
        var sizeFormatted: String { ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file) }
    }

    /// Recursive size of a directory in bytes.
    static func directorySizeBytes(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let resource = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                  resource.isDirectory != true,
                  let size = resource.fileSize else { continue }
            total += Int64(size)
        }
        return total
    }

    /// List SLM cache: top-level files and subdirs with total size each. Returns display-friendly items.
    static func listSLMCache() -> [CachedSLMItem] {
        let fm = FileManager.default
        let url = slmModelsURL
        guard fm.fileExists(atPath: url.path),
              let contents = try? fm.contentsOfDirectory(
                  at: url,
                  includingPropertiesForKeys: [.isDirectoryKey],
                  options: [.skipsHiddenFiles]
              ) else {
            return []
        }
        return contents.map { itemURL in
            let name = itemURL.lastPathComponent
            let isDir = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            let size: Int64
            if isDir {
                size = directorySizeBytes(at: itemURL)
            } else {
                size = (try? fm.attributesOfItem(atPath: itemURL.path)[.size] as? Int64) ?? 0
            }
            return CachedSLMItem(id: itemURL.path, name: name, sizeBytes: size)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Total size of the full model cache (FluidAudio STT + Mów SLM directories).
    static func totalCacheSizeBytes() -> Int64 {
        directorySizeBytes(at: fluidAudioModelsURL) + directorySizeBytes(at: slmModelsURL)
    }

    /// Remove all contents of the SLM cache directory. Call after unloading SLM if needed.
    /// Does not remove the directory itself.
    static func clearSLMCache() throws {
        let fm = FileManager.default
        let url = slmModelsURL
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: []
        ) else { return }
        for item in contents {
            try? fm.removeItem(at: item)
        }
    }
}
