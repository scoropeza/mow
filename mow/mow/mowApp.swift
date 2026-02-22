//
//  mowApp.swift
//  mow
//

import SwiftUI

@main
struct MowApp: App {
    @State private var statusManager = StatusManager()
    @State private var launchAtLoginService = LaunchAtLoginService()
    @State private var recordingCoordinator = RecordingCoordinator()
    @State private var modelManager = ModelManager()
    init() {
        // No automatic permission requests. User grants Microphone and Accessibility via Settings;
        // bootstrap (models, shortcut) runs when the menu is opened and both permissions are granted.
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenuView(
                statusManager: statusManager,
                recordingCoordinator: recordingCoordinator,
                modelManager: modelManager
            )
        } label: {
            MenuBarStatusIconWithLaunchBootstrap(
                statusManager: statusManager,
                recordingCoordinator: recordingCoordinator,
                modelManager: modelManager
            )
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: "settings") {
            SettingsView(launchAtLoginService: launchAtLoginService, recordingCoordinator: recordingCoordinator)
        }
        .defaultSize(width: 440, height: 340)
        .windowResizability(.contentSize)

        Window("Model Management", id: "modelManagement") {
            ModelManagementView(modelManager: modelManager)
        }
        .defaultSize(width: 360, height: 220)
        .windowResizability(.contentSize)

        Window("Logs", id: "logs") {
            LogsView()
        }
        .defaultSize(width: 360, height: 200)
        .windowResizability(.contentSize)

        Window("About Mów", id: "about") {
            AboutMowView()
        }
        .defaultSize(width: 280, height: 220)
        .windowResizability(.contentSize)

        Window("", id: "launcher") {
            PermissionWindowLauncherView()
        }
        .defaultSize(width: 1, height: 1)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultPosition(.init(x: -10000, y: -10000))

        Window("Microphone Permission", id: "microphonePermission") {
            MicrophonePermissionRequestView()
        }
        .defaultSize(width: 320, height: 180)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .windowStyle(.hiddenTitleBar)
    }
}
