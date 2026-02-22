//
//  MenuBarMenuView.swift
//  mow
//
//  Menu bar dropdown: Settings, Model Management, View Logs, About, Quit. Recording is via the global shortcut only.
//

import AVFoundation
import Combine
import SwiftUI

struct MenuBarMenuView: View {
    @Bindable var statusManager: StatusManager
    var recordingCoordinator: RecordingCoordinator
    var modelManager: ModelManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            Button("Settings") {
                openWindow(id: "settings")
            }

            Button("Model Management") {
                openWindow(id: "modelManagement")
            }

            if statusManager.status.isError {
                Button("View Logs") {
                    openWindow(id: "logs")
                }
            }

            Divider()

            Button("About Mów", action: showAbout)

            Button("Quit Mów") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
        .controlSize(.large)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .frame(width: 220)
        .frame(minHeight: 180)
        .onAppear {
            AppBootstrap.setRefs(
                coordinator: recordingCoordinator,
                statusManager: statusManager,
                modelManager: modelManager
            )
            if MicrophonePermission.status() == .authorized && AccessibilityPermission.isGranted {
                AppBootstrap.runIfNeeded()
            } else {
                statusManager.status = .permissionsNeeded
            }
            MicrophonePermissionWindowState.shared.onClose = { [recordingCoordinator] in
                recordingCoordinator.startShortcutMonitor()
            }
        }
    }

    private func showAbout() {
        openWindow(id: "about")
    }
}
