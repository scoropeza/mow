//
//  PermissionWindowLauncherView.swift
//  mow
//
//  Invisible helper: opens the permission window when needed and bootstraps the app (coordinator, shortcut, models)
//  so the global shortcut works even if the user never opens the menu.
//

import Combine
import SwiftUI

struct PermissionWindowLauncherView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var state = MicrophonePermissionWindowState.shared

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onChange(of: state.showPermissionWindow) { _, new in
                if new {
                    openWindow(id: "microphonePermission")
                    state.showPermissionWindow = false
                }
            }
            .onAppear {
                AppBootstrap.runIfNeeded()
            }
    }
}
