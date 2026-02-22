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

    func startRecording() {
        guard status == .ready else { return }
        isRecording = true
    }

    func stopRecording() {
        isRecording = false
    }
}
