//
//  MicrophonePermissionRequestView.swift
//  mow
//
//  Shown in a key window so the system microphone "Allow" dialog can appear.
//  TCC often suppresses the prompt when the app has no key window (e.g. menu bar only).
//

import AVFoundation
import AppKit
import Combine
import SwiftUI

/// Find the Microphone Permission window and make it key (title can vary or be empty in Release/DMG).
private func makeMicrophonePermissionWindowKey() {
    for window in NSApp.windows {
        let title = window.title
        if title == "Microphone Permission" || title.contains("Microphone") {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }
    // Fallback: in Release/DMG the window title can be empty (e.g. hidden title bar).
    // Use the frontmost visible window of our size.
    for window in NSApp.windows {
        guard window.isVisible else { continue }
        let size = window.frame.size
        if size.width >= 300 && size.width <= 400 && size.height >= 150 && size.height <= 250 {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }
}

struct MicrophonePermissionRequestView: View {
    @ObservedObject private var windowState = MicrophonePermissionWindowState.shared
    @State private var didRequest = false
    @State private var statusMessage = "Preparing…"

    var body: some View {
        VStack(spacing: 16) {
            Text("Microphone Access")
                .font(.headline)
            Text(statusMessage)
                .font(.body)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Button("Close") {
                if let comp = windowState.completion {
                    windowState.completion = nil
                    comp(MicrophonePermission.status() == .authorized)
                }
                windowState.onClose?()
                NSApp.keyWindow?.close()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: 320)
        .onAppear {
            guard !didRequest else { return }
            didRequest = true
            NSApp.activate(ignoringOtherApps: true)
            statusMessage = "Requesting microphone access…"
            // Make this window key on next run loop (so it exists when opened from Settings in Release/DMG).
            DispatchQueue.main.async { makeMicrophonePermissionWindowKey() }
            // Request after delay so window exists and is key. Call requestAccess in same run loop as makeKey
            // so TCC has a key window to attach the system prompt to (critical for DMG/Release builds).
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                NSApp.activate(ignoringOtherApps: true)
                makeMicrophonePermissionWindowKey()
                AVCaptureDevice.requestAccess(for: .audio, completionHandler: { granted in
                    DispatchQueue.main.async {
                        statusMessage = granted
                            ? "Access granted. You can close this window."
                            : "Denied or dialog didn’t appear. Run: tccutil reset Microphone com.daedalus-labs.mow"
                        if let comp = windowState.completion {
                            windowState.completion = nil
                            comp(granted)
                        }
                    }
                })
            }
        }
    }
}
