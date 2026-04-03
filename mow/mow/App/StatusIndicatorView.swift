//
//  StatusIndicatorView.swift
//  mow
//
//  Menu bar status indicator: purple (permissions needed), yellow (loading), green (ready), red (error).
//  Uses .symbolRenderingMode(.palette) so the menu bar shows our color instead of template white.
//

import AVFoundation
import SwiftUI

struct StatusIndicatorView: View {
    let status: AppStatus
    let isRecording: Bool

    var body: some View {
        Image(systemName: isRecording ? "record.circle.fill" : "circle.fill")
            .font(.system(size: isRecording ? 12 : 8, weight: .medium))
            .symbolRenderingMode(.palette)
            .foregroundStyle(isRecording ? .red : status.color)
    }
}

/// Menu bar label: colored dot when idle, red record icon while recording,
/// latency text (e.g. "✓ 1.2s") briefly after dictation when developer flag is on.
struct MenuBarStatusIcon: View {
    @Bindable var statusManager: StatusManager

    var body: some View {
        if let latency = statusManager.latencyText {
            Text(latency)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.green)
        } else {
            StatusIndicatorView(
                status: statusManager.status,
                isRecording: statusManager.isRecording
            )
        }
    }
}

/// Menu bar label that runs bootstrap on appear so status (icon color) updates at launch without opening the menu.
struct MenuBarStatusIconWithLaunchBootstrap: View {
    @Bindable var statusManager: StatusManager
    var recordingCoordinator: RecordingCoordinator
    var modelManager: ModelManager

    var body: some View {
        MenuBarStatusIcon(statusManager: statusManager)
            .onAppear {
                AppBootstrap.setRefs(
                    coordinator: recordingCoordinator,
                    statusManager: statusManager,
                    modelManager: modelManager
                )
                if MicrophonePermission.status() == .authorized && AccessibilityPermission.isGranted {
                    AppBootstrap.runIfNeeded()
                } else {
                    statusManager.setPermissionsNeeded()
                }
            }
    }
}
