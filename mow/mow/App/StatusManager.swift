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
}
