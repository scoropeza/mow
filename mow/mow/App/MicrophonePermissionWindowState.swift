//
//  MicrophonePermissionWindowState.swift
//  mow
//
//  Shared state so we can open the microphone permission window from non-View code.
//  TCC permission dialogs require a key window; menu bar apps often have none at launch.
//

import Combine
import Foundation
import SwiftUI

/// When true, the app should present the Microphone Permission window. The window requests access
/// so the system "Allow" dialog has a key window to attach to.
final class MicrophonePermissionWindowState: ObservableObject {
    static let shared = MicrophonePermissionWindowState()

    @Published var showPermissionWindow = false
    /// Set by MicrophonePermission before opening the window; called when the request finishes.
    var completion: ((Bool) -> Void)?
    /// Called when the permission window is closed (e.g. to restart the shortcut monitor).
    var onClose: (() -> Void)?

    private init() {}
}
