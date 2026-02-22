//
//  MicrophonePermission.swift
//  mow
//
//  Request and handle microphone permission; clear error if denied.
//

import AVFoundation
import AppKit
import Foundation
import os

enum MicrophonePermission {
    /// Only show the "denied" alert once per launch to avoid spamming when shortcut is pressed repeatedly.
    private static var didShowDeniedAlertThisLaunch = false

    /// Check current authorization status.
    static func status() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    /// Human-readable status for UI (e.g. Settings).
    static func statusString() -> String {
        switch status() {
        case .authorized: return "Authorized"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not determined"
        @unknown default: return "Unknown"
        }
    }

    /// Open System Settings → Privacy & Security → Microphone.
    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Request access if not determined. Call from main thread; completion on main thread.
    static func requestAccess(completion: @escaping (Bool) -> Void) {
        switch status() {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    if granted {
                        appLog.info("Microphone access granted")
                    } else {
                        appLog.warning("Microphone access denied")
                        Self.showDeniedAlert()
                        AppErrorState.set(
                            "Microphone access was denied. Enable it in System Settings → " +
                            "Privacy & Security → Microphone."
                        )
                    }
                    completion(granted)
                }
            }
        case .denied, .restricted:
            showDeniedAlert()
            AppErrorState.set(
                "Microphone access is denied. Enable Mów in System Settings → Privacy & Security → Microphone."
            )
            completion(false)
        @unknown default:
            completion(false)
        }
    }

    /// Call this to trigger the system Allow/Don't Allow dialog. Only shows if status is .notDetermined
    /// (e.g. after tccutil reset). Use from Settings so the user can trigger right after resetting.
    static func triggerSystemPrompt(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                if granted { appLog.info("Microphone access granted") }
                completion(granted)
            }
        }
    }

    /// Returns true if we can use the microphone (authorized). If not determined, opens a key window
    /// and requests there so the system "Allow" dialog can show (TCC often suppresses it for menu bar apps).
    static func ensureAccess(completion: @escaping (Bool) -> Void) {
        switch status() {
        case .authorized:
            completion(true)
        case .notDetermined:
            let state = MicrophonePermissionWindowState.shared
            state.completion = completion
            DispatchQueue.main.async {
                state.showPermissionWindow = true
            }
        case .denied, .restricted:
            showDeniedAlert()
            AppErrorState.set(
                "Microphone access is denied. Enable Mów in System Settings → Privacy & Security → Microphone."
            )
            completion(false)
        @unknown default:
            completion(false)
        }
    }

    private static func showDeniedAlert() {
        guard !didShowDeniedAlertThisLaunch else { return }
        didShowDeniedAlertThisLaunch = true
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Microphone Access Required"
            alert.informativeText = """
            Mów needs microphone access for voice-to-text. The system didn’t show an "Allow" prompt, and you can’t \
            add the app from the empty Microphone list—you must reset so the system asks again.

            1. Quit Mów (menu bar icon → Quit Mów).
            2. Open Terminal (Spotlight: Terminal) and run:
               tccutil reset Microphone com.daedalus-labs.mow
            3. Open Mów from Applications (or use Settings → "Request microphone access" after opening).
            4. When the system dialog appears, click "Allow".

            Then microphone access will work. (On some Macs the app still won’t appear in the list; \
            if dictation works, you’re set.)
            """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "OK")
            if alert.runModal() == .alertFirstButtonReturn {
                openSystemSettings()
            }
        }
    }
}
