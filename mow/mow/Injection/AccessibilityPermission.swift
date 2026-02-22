//
//  AccessibilityPermission.swift
//  mow
//
//  Check and prompt for Accessibility permission (8.2). Required for text injection and global shortcut.
//

import AppKit
import ApplicationServices
import Foundation

enum AccessibilityPermission {
    /// Whether the app is trusted for Accessibility (required for injection and global shortcut).
    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Open System Settings (or System Preferences) to the Privacy & Security → Accessibility pane.
    /// Call when permission is missing so the user can enable Mów.
    static func openSystemSettings() {
        if #available(macOS 13.0, *) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        } else {
            let script = "tell application \"System Preferences\" to reveal anchor " +
                "\"Privacy_Accessibility\" of pane id \"com.apple.preference.security\""
            NSAppleScript(source: script)?.executeAndReturnError(nil)
            NSWorkspace.shared.launchApplication("System Preferences")
        }
    }

    /// User-facing message when Accessibility is not granted.
    static let instructionsWhenDenied = "Mów needs Accessibility permission to type transcribed text "
        + "into the active app and to use the global shortcut.\n\n"
        + "Enable \"Mów\" in System Settings → Privacy & Security → Accessibility, then restart Mów."
}
