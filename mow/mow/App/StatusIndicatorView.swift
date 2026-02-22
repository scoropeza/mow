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

    var body: some View {
        Image(systemName: "circle.fill")
            .font(.system(size: 8, weight: .medium))
            .symbolRenderingMode(.palette)
            .foregroundStyle(status.color)
    }
}

/// Menu bar label: purple when permissions needed, yellow loading, green ready, red error.
struct MenuBarStatusIcon: View {
    @Bindable var statusManager: StatusManager

    var body: some View {
        StatusIndicatorView(status: statusManager.status)
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
