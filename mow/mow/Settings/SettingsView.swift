//
//  SettingsView.swift
//  mow
//
//  Settings window: shortcut, models, launch at login, etc.
//

import SwiftUI

struct SettingsView: View {
    @Bindable var launchAtLoginService: LaunchAtLoginService
    var recordingCoordinator: RecordingCoordinator
    @Environment(\.openWindow) private var openWindow
    @State private var slmPromptText: String = SLMPromptStorage.currentPrompt
    @State private var textCleaningEnabled: Bool = TextCleaningSettings.isEnabled
    @State private var micStatus: String = ""
    @State private var showMicResetHint: Bool = false
    @State private var accessibilityStatus: String = ""
    @State private var showDictationLatency: Bool = DictationLatencySettings.isEnabled

    var body: some View {
        Form {
            Section("Microphone") {
                HStack {
                    Text("Status:")
                    Spacer()
                    Text(micStatus)
                        .foregroundStyle(micStatus == "Authorized" ? .secondary : .primary)
                }
                Button("Request microphone access") {
                    let state = MicrophonePermissionWindowState.shared
                    state.completion = { _ in
                        micStatus = MicrophonePermission.statusString()
                        showMicResetHint = (MicrophonePermission.statusString() == "Denied")
                    }
                    openWindow(id: "microphonePermission")
                }
                .disabled(micStatus == "Authorized")
                Button("Open Microphone Settings") {
                    MicrophonePermission.openSystemSettings()
                }
                if showMicResetHint {
                    Text("System dialog didn’t appear. Quit Mów, run in Terminal: tccutil reset Microphone "
                        + "com.daedalus-labs.mow then open Mów and click \"Request microphone access\" again.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text("Mów needs microphone access for voice-to-text. On some Macs, menu bar apps don’t appear "
                    + "in the list even when access is granted—if dictation works, you’re all set.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLoginService.isEnabled)
                Text("Works when the app is in the Applications folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Accessibility") {
                HStack {
                    Text("Status:")
                    Spacer()
                    Text(accessibilityStatus)
                        .foregroundStyle(accessibilityStatus == "Granted" ? .secondary : .primary)
                }
                Button("Open Accessibility Settings") {
                    AccessibilityPermission.openSystemSettings()
                }
                Text("Required for the global shortcut and for typing transcribed text into other apps. "
                    + "Add Mów and turn it on, then restart Mów.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Keyboard Shortcut") {
                ShortcutRecorderView(recordingCoordinator: recordingCoordinator)
                Button("Restart shortcut") {
                    recordingCoordinator.updateShortcutAndRestartMonitor()
                }
                Text("Trigger is Option + the key above (e.g. ⌥ M). Hold to record, release to stop. "
                    + "If the shortcut stops working in other apps, click \"Restart shortcut\" or enable Mów "
                    + "in System Settings → Privacy & Security → Accessibility.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Text cleaning") {
                Toggle("Enable text cleaning", isOn: $textCleaningEnabled)
                    .onChange(of: textCleaningEnabled) { _, new in
                        TextCleaningSettings.isEnabled = new
                    }
                Text("When off, raw transcription is used without removing fillers or disfluencies.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("SLM system prompt (takes effect after app restart)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $slmPromptText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 80, maxHeight: 160)
                    .onChange(of: slmPromptText) { _, new in
                        SLMPromptStorage.currentPrompt = new
                    }
                Button("Reset to default") {
                    SLMPromptStorage.resetToDefault()
                    slmPromptText = SLMPromptStorage.currentPrompt
                }
            }
            Section("Logs") {
                Button("Open Logs Window") {
                    openWindow(id: "logs")
                }
                Text("View last transcription and any errors.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Developer") {
                Toggle("Show dictation latency", isOn: $showDictationLatency)
                    .onChange(of: showDictationLatency) { _, new in
                        DictationLatencySettings.isEnabled = new
                    }
                Text("Briefly show total latency (e.g. ✓ 1.2s) in the menu bar after each dictation. "
                    + "Timing breakdown is always logged regardless of this setting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 400, minHeight: 300)
        .onAppear {
            slmPromptText = SLMPromptStorage.currentPrompt
            textCleaningEnabled = TextCleaningSettings.isEnabled
            micStatus = MicrophonePermission.statusString()
            accessibilityStatus = AccessibilityPermission.isGranted ? "Granted" : "Not granted"
            showMicResetHint = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            micStatus = MicrophonePermission.statusString()
            accessibilityStatus = AccessibilityPermission.isGranted ? "Granted" : "Not granted"
        }
    }
}
