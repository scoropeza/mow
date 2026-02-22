//
//  LaunchAtLoginService.swift
//  mow
//
//  Optional launch at login via SMAppService (macOS 13+).
//

import Foundation
import os
import ServiceManagement
import SwiftUI

private let launchAtLoginKey = "launchAtLoginEnabled"

/// Manages the "Launch at login" setting and SMAppService registration.
@Observable
final class LaunchAtLoginService {
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            UserDefaults.standard.set(isEnabled, forKey: launchAtLoginKey)
            applyRegistration()
        }
    }

    var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    init() {
        self.isEnabled = UserDefaults.standard.object(forKey: launchAtLoginKey) as? Bool ?? false
        // Do not sync on init: registering from Xcode/DerivedData fails with "Operation not permitted".
        // Registration runs only when the user toggles the switch in Settings.
    }

    private func applyRegistration() {
        do {
            if isEnabled {
                try SMAppService.mainApp.register()
                appLog.info("Launch at login registered")
            } else {
                try SMAppService.mainApp.unregister()
                appLog.info("Launch at login unregistered")
            }
        } catch {
            appLog.error("Launch at login failed: \(error.localizedDescription)")
            // Don't set AppErrorState for "operation not permitted" (e.g. running from Xcode/DerivedData).
            let msg = error.localizedDescription.lowercased()
            if msg.contains("not permitted") || msg.contains("operation not permitted") {
                // Expected when running from Xcode; works when app is in /Applications.
                return
            }
            AppErrorState.set("Launch at login: \(error.localizedDescription)")
        }
    }
}
