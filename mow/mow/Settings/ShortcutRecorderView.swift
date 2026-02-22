//
//  ShortcutRecorderView.swift
//  mow
//
//  UI to display and record the global dictation shortcut (task 4.3).
//

import AppKit
import Carbon
import SwiftUI

/// Modifier flags we care about for the shortcut (exclude caps lock, etc.).
private let shortcutModifierMask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

@Observable
final class ShortcutRecorderState {
    var currentShortcut = DictationShortcut.load()
    var isRecording = false
    private var localMonitor: Any?
    private weak var coordinator: RecordingCoordinator?

    func setCoordinator(_ coordinator: RecordingCoordinator) {
        self.coordinator = coordinator
    }

    func startRecording() {
        isRecording = true
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if event.keyCode == UInt16(kVK_Escape) {
                DispatchQueue.main.async { self.finishRecording(cancelled: true) }
                return nil
            }
            let mods = event.modifierFlags.intersection(shortcutModifierMask)
            let shortcut = DictationShortcut(
                keyCode: UInt32(event.keyCode),
                modifiers: UInt32(mods.rawValue)
            )
            shortcut.save()
            DispatchQueue.main.async {
                self.currentShortcut = shortcut
                self.finishRecording(cancelled: false)
                self.coordinator?.updateShortcutAndRestartMonitor()
            }
            return nil
        }
    }

    private func finishRecording(cancelled: Bool) {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        isRecording = false
    }
}

struct ShortcutRecorderView: View {
    var recordingCoordinator: RecordingCoordinator
    @State private var state = ShortcutRecorderState()

    var body: some View {
        HStack {
            Text(state.currentShortcut.displayString)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(state.isRecording ? .secondary : .primary)
                .frame(minWidth: 120, alignment: .leading)
            if state.isRecording {
                Text("Press key combination… (Escape to cancel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("Record…") {
                    state.setCoordinator(recordingCoordinator)
                    state.startRecording()
                }
            }
        }
        .onAppear {
            state.currentShortcut = DictationShortcut.load()
        }
    }
}
