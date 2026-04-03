//
//  StatusManager.swift
//  mow
//
//  Manages app status for the menu bar indicator and recording state.
//

import SwiftUI

@Observable
final class StatusManager {
    var status: AppStatus = .permissionsNeeded
    var isRecording: Bool = false
    /// When non-nil, the menu bar shows this text (e.g. "✓ 1.2s") instead of the dot icon.
    var latencyText: String?

    func setPermissionsNeeded() {
        status = .permissionsNeeded
    }

    func setLoading() {
        status = .loading
    }

    func setReady() {
        status = .ready
    }

    func setError() {
        status = .error
    }

    /// Set warning status (orange dot) that automatically recovers to ready after a delay.
    /// Use for transient issues (short recording, quiet audio, STT failure) where the user can retry.
    func setTransientError() {
        status = .warning
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self, self.status == .warning else { return }
            self.status = .ready
        }
    }

    func startRecording() {
        guard status == .ready || status == .warning else { return }
        isRecording = true
    }

    func stopRecording() {
        isRecording = false
    }

    /// Briefly show latency in the menu bar, then revert to the dot after 3 seconds.
    func showLatency(_ seconds: Double) {
        guard DictationLatencySettings.isEnabled else { return }
        latencyText = String(format: "✓ %.1fs", seconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self else { return }
            self.latencyText = nil
        }
    }
}
