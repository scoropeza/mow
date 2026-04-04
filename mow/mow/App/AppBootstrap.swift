//
//  AppBootstrap.swift
//  mow
//
//  Runs coordinator setup and shortcut monitor so the global shortcut works even when
//  no window appears at launch (e.g. launcher window may not be shown by SwiftUI).
//

import AVFoundation
import Foundation

enum AppBootstrap {
    private static var didRun = false
    static weak var coordinator: RecordingCoordinator?
    static weak var statusManager: StatusManager?
    static weak var modelManager: ModelManager?

    /// Call from App body so refs are set when the delayed bootstrap runs.
    static func setRefs(
        coordinator: RecordingCoordinator,
        statusManager: StatusManager,
        modelManager: ModelManager
    ) {
        self.coordinator = coordinator
        self.statusManager = statusManager
        self.modelManager = modelManager
    }

    /// Run setup once when both Microphone and Accessibility are granted: configure coordinator,
    /// start shortcut monitor, load models.
    static func runIfNeeded() {
        guard !didRun else { return }
        guard let coordinator = coordinator,
              let statusManager = statusManager,
              let modelManager = modelManager else { return }
        guard MicrophonePermission.status() == .authorized, AccessibilityPermission.isGranted else {
            statusManager.setPermissionsNeeded()
            return
        }
        didRun = true
        coordinator.setStatusManager(statusManager)
        coordinator.setSpeechToTextService(modelManager.sttService)
        coordinator.setTextCleaningService(modelManager.textCleaningService)
        statusManager.setLoading()

        // Load disfluency classifier in background (non-blocking)
        Task {
            await modelManager.textCleaningService.loadDisfluencyClassifier()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            coordinator.startShortcutMonitor()
        }
        modelManager.loadModelsAtLaunch(
            onSLMLoadFailure: { error in
                AppErrorState.set("Text cleaning model: \(error.localizedDescription)")
                statusManager.setError()
            },
            onSLMInferenceError: {
                AppErrorState.set("Text cleaning failed")
                statusManager.setError()
            },
            completion: { result in
                switch result {
                case .success:
                    statusManager.setReady()
                    coordinator.startShortcutMonitor()
                case .failure(let error):
                    AppErrorState.set("Speech model: \(error.localizedDescription)")
                    statusManager.setError()
                }
            }
        )
    }
}
