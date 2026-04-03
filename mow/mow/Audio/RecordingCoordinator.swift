//
//  RecordingCoordinator.swift
//  mow
//
//  Coordinates mic permission, audio capture, and global shortcut for dictation.
//  Start/stop on shortcut (or menu); only records when status is ready.
//

import AppKit
import Foundation
import os

/// Coordinates recording: permission check, buffered capture, and shortcut. Call from main thread.
final class RecordingCoordinator {
    private let audioCapture = AudioCaptureService()
    private var shortcutMonitor: GlobalShortcutMonitor?
    private weak var statusManager: StatusManager?
    private weak var speechToTextService: SpeechToTextService?
    private weak var textCleaningService: TextCleaningService?
    private var shortcutMonitorStarted = false
    /// Time when shortcut was released (for optional latency benchmark, task 13.4).
    private var shortcutUpTimestamp: CFAbsoluteTime = 0
    /// The app and focused element when recording stopped, so we can inject text back to the right place.
    private var injectionTarget: InjectionTarget?

    func setStatusManager(_ manager: StatusManager) {
        statusManager = manager
    }

    func setSpeechToTextService(_ service: SpeechToTextService) {
        speechToTextService = service
    }

    func setTextCleaningService(_ service: TextCleaningService) {
        textCleaningService = service
    }

    /// Start global shortcut monitoring. Uses persisted shortcut (UserDefaults).
    /// Idempotent; retries if tap failed (e.g. at launch).
    func startShortcutMonitor() {
        if shortcutMonitorStarted { return }
        let shortcut = DictationShortcut.load()
        let monitor = GlobalShortcutMonitor(
            shortcut: shortcut,
            onShortcutDown: { [weak self] in self?.onShortcutDown() },
            onShortcutUp: { [weak self] in self?.onShortcutUp() }
        )
        shortcutMonitor = monitor
        if monitor.start() {
            shortcutMonitorStarted = true
        } else {
            shortcutMonitor = nil
        }
    }

    func stopShortcutMonitor() {
        shortcutMonitor?.stop()
        shortcutMonitor = nil
        shortcutMonitorStarted = false
    }

    /// Restart the shortcut monitor with the current persisted shortcut (e.g. after user changed it in Settings).
    func updateShortcutAndRestartMonitor() {
        stopShortcutMonitor()
        shortcutMonitorStarted = false
        startShortcutMonitor()
    }

    /// Start recording (from menu or shortcut). Checks mic permission and status; accumulates until stop.
    func startRecording() {
        guard let statusManager = statusManager,
              statusManager.status == .ready || statusManager.status == .warning else {
            audioLog.debug("Ignoring start: status not ready")
            return
        }
        MicrophonePermission.ensureAccess { [weak self] granted in
            guard granted, let self = self else { return }
            do {
                try self.audioCapture.startCaptureBuffered()
                statusManager.startRecording()
            } catch let err as AudioCaptureError {
                Self.handleCaptureError(err, statusManager: statusManager)
            } catch {
                appLog.error("Failed to start capture: \(error.localizedDescription)")
                AppErrorState.set("Microphone: \(error.localizedDescription)")
                statusManager.setTransientError()
            }
        }
    }

    private static func handleCaptureError(_ error: AudioCaptureError, statusManager: StatusManager) {
        appLog.error("Capture error: \(error.localizedDescription)")
        AppErrorState.set(error.errorDescription ?? error.localizedDescription)
        statusManager.setTransientError()
        if case .noInputAvailable = error {
            Self.showNoMicrophoneAlert()
        }
    }

    private static func showNoMicrophoneAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "No Microphone Found"
            alert.informativeText = "Connect a microphone or select one in System Settings → Sound → Input."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    /// Stop recording and receive the full buffer (16 kHz mono Float32). Call from main.
    func stopRecording(completion: @escaping ([Float]) -> Void = { _ in }) {
        guard statusManager?.isRecording == true else {
            completion([])
            return
        }
        // Capture the frontmost app and focused element NOW, before transcription shifts focus.
        injectionTarget = InjectionTarget.capture()
        statusManager?.stopRecording()
        audioCapture.stopCaptureBuffered { [weak self] samples in
            if !samples.isEmpty {
                let quality = AudioQualityCheck.check(samples: samples)
                if let message = quality.userMessage {
                    audioLog.warning("\(message)")
                    AppErrorState.set(message)
                    self?.statusManager?.setTransientError()
                }
                let duration = Double(samples.count) / AudioCaptureConstants.sampleRate
                audioLog.info("Captured \(samples.count) samples (\(String(format: "%.2f", duration)) s)")
                self?.runSTTOnSamples(samples)
            }
            completion(samples)
        }
    }

    private func onShortcutDown() {
        startRecording()
    }

    private func onShortcutUp() {
        shortcutUpTimestamp = CFAbsoluteTimeGetCurrent()
        stopRecording()
    }

    /// Run STT on captured 16 kHz mono Float32 samples; log raw transcription and surface errors (tasks 5.3, 5.5, 9.x).
    private func runSTTOnSamples(_ samples: [Float]) {
        guard let service = speechToTextService, service.isReady else {
            audioLog.debug("STT not ready, skipping transcription")
            return
        }
        let target = injectionTarget
        Task {
            await MainActor.run { self.statusManager?.setLoading() }
            let pipelineStart = CFAbsoluteTimeGetCurrent()
            do {
                let sttStart = CFAbsoluteTimeGetCurrent()
                let rawText = try await service.transcribe(samples: samples)
                let sttElapsed = CFAbsoluteTimeGetCurrent() - sttStart

                let text: String
                var slmElapsed: Double = 0
                if rawText.isEmpty {
                    text = ""
                } else if let cleaner = textCleaningService {
                    let slmStart = CFAbsoluteTimeGetCurrent()
                    text = await cleaner.clean(rawText: rawText)
                    slmElapsed = CFAbsoluteTimeGetCurrent() - slmStart
                } else {
                    text = rawText
                }
                let totalElapsed = CFAbsoluteTimeGetCurrent() - pipelineStart
                await MainActor.run {
                    if text.isEmpty {
                        audioLog.debug("Transcription empty")
                        self.statusManager?.setReady()
                    } else {
                        AppTranscriptionState.set(text)
                        let textForUser = ThinkingStrip.finalAnswer(from: text)
                        if !AccessibilityPermission.isGranted {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(textForUser, forType: .string)
                            AppErrorState.set(AccessibilityPermission.instructionsWhenDenied)
                            self.statusManager?.setError()
                        } else {
                            _ = TextInjectionService.inject(textForUser, target: target)
                            self.statusManager?.setReady()
                            self.statusManager?.showLatency(totalElapsed)
                        }
                    }
                    self.logTimingBreakdown(stt: sttElapsed, slm: slmElapsed, total: totalElapsed)
                    self.injectionTarget = nil
                    self.logDictationLatencyIfNeeded()
                }
            } catch {
                await MainActor.run {
                    errorLog.error("STT inference failed: \(error.localizedDescription)")
                    appLog.error("STT failed: \(error.localizedDescription)")
                    AppErrorState.set("Transcription: \(error.localizedDescription)")
                    self.injectionTarget = nil
                    self.statusManager?.setTransientError()
                    self.logDictationLatencyIfNeeded()
                }
            }
        }
    }

    /// Log timing breakdown to the persistent log file (always) and os.log (always).
    private func logTimingBreakdown(stt: Double, slm: Double, total: Double) {
        let sttStr = String(format: "%.2f", stt)
        let slmStr = String(format: "%.2f", slm)
        let totalStr = String(format: "%.2f", total)
        let breakdown = "Latency: \(totalStr)s total (STT \(sttStr)s + clean \(slmStr)s)"
        modelLog.info("\(breakdown)")
        LogFileManager.append("[timing] \(breakdown)")
    }

    /// Log time from shortcut release to text injected (or error). Optional benchmark (task 13.4).
    private func logDictationLatencyIfNeeded() {
        guard shortcutUpTimestamp > 0 else { return }
        let elapsed = CFAbsoluteTimeGetCurrent() - shortcutUpTimestamp
        modelLog.info("Dictation latency (shortcut release → text): \(String(format: "%.2f", elapsed)) s")
        shortcutUpTimestamp = 0
    }
}
