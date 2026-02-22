//
//  GlobalShortcutMonitor.swift
//  mow
//
//  Global keyboard shortcut: start recording on key down, stop on key up (press-and-hold).
//  Uses CGEventTap; requires Accessibility (or Input Monitoring) permission.
//

import AppKit
import Carbon
import CoreGraphics
import Foundation
import os

/// Dictation shortcut (key + modifiers). Persisted in UserDefaults; used for global hotkey.
struct DictationShortcut: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let `default` = DictationShortcut(
        keyCode: UInt32(kVK_ANSI_M),
        modifiers: UInt32(CGEventFlags.maskAlternate.rawValue)
    )

    private static let keyCodeKey = "dictationShortcutKeyCode"
    private static let modifiersKey = "dictationShortcutModifiers"

    static func load() -> DictationShortcut {
        let ud = UserDefaults.standard
        guard ud.object(forKey: keyCodeKey) != nil,
              ud.object(forKey: modifiersKey) != nil else {
            return .default
        }
        let code = UInt32(ud.integer(forKey: keyCodeKey))
        let mods = UInt32(ud.integer(forKey: modifiersKey))
        return DictationShortcut(keyCode: code, modifiers: mods)
    }

    func save() {
        UserDefaults.standard.set(Int(keyCode), forKey: Self.keyCodeKey)
        UserDefaults.standard.set(Int(modifiers), forKey: Self.modifiersKey)
    }

    /// Human-readable label (e.g. "⌥ Space").
    var displayString: String {
        var parts: [String] = []
        let mods = Int(modifiers)
        if (mods & Int(NSEvent.ModifierFlags.command.rawValue)) != 0 { parts.append("⌘") }
        if (mods & Int(NSEvent.ModifierFlags.option.rawValue)) != 0 { parts.append("⌥") }
        if (mods & Int(NSEvent.ModifierFlags.control.rawValue)) != 0 { parts.append("⌃") }
        if (mods & Int(NSEvent.ModifierFlags.shift.rawValue)) != 0 { parts.append("⇧") }
        parts.append(keyDisplayName)
        return parts.joined(separator: " ")
    }

    private var keyDisplayName: String {
        switch keyCode {
        case UInt32(kVK_Space): return "Space"
        case UInt32(kVK_ANSI_M): return "M"
        case UInt32(kVK_Return): return "Return"
        case UInt32(kVK_Tab): return "Tab"
        case UInt32(kVK_Delete): return "Delete"
        case UInt32(kVK_Escape): return "Escape"
        case UInt32(kVK_ANSI_0): return "0"
        case UInt32(kVK_ANSI_1): return "1"
        case UInt32(kVK_ANSI_2): return "2"
        case UInt32(kVK_ANSI_3): return "3"
        case UInt32(kVK_ANSI_4): return "4"
        case UInt32(kVK_ANSI_5): return "5"
        case UInt32(kVK_ANSI_6): return "6"
        case UInt32(kVK_ANSI_7): return "7"
        case UInt32(kVK_ANSI_8): return "8"
        case UInt32(kVK_ANSI_9): return "9"
        default: return "Key \(keyCode)"
        }
    }

    func matches(event: CGEvent) -> Bool {
        let code = UInt32(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags.rawValue
        let modMask = UInt64(modifiers)
        return code == keyCode && (flags & modMask) == modMask
    }
}

private func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<GlobalShortcutMonitor>.fromOpaque(refcon).takeUnretainedValue()
    if monitor.shortcut.matches(event: event) {
        if type == .keyDown {
            if !monitor.keyIsDown {
                monitor.keyIsDown = true
                DispatchQueue.main.async { monitor.onShortcutDown() }
            }
            return nil  // Consume keyDown so Option+M doesn't type a character
        }
        if type == .keyUp {
            monitor.keyIsDown = false
            DispatchQueue.main.async { monitor.onShortcutUp() }
            // Pass keyUp through so the system's keyboard state stays in sync;
            // consuming it can leave 'm' stuck and break subsequent keypresses.
            return Unmanaged.passUnretained(event)
        }
    }
    return Unmanaged.passUnretained(event)
}

/// Monitors global key down/up for the dictation shortcut and invokes callbacks (on main queue).
final class GlobalShortcutMonitor {
    private static var hasLoggedAccessibilityWarning = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    fileprivate var shortcut: DictationShortcut
    fileprivate var keyIsDown = false
    fileprivate let onShortcutDown: () -> Void
    fileprivate let onShortcutUp: () -> Void

    init(shortcut: DictationShortcut = .default, onShortcutDown: @escaping () -> Void, onShortcutUp: @escaping () -> Void) {
        self.shortcut = shortcut
        self.onShortcutDown = onShortcutDown
        self.onShortcutUp = onShortcutUp
    }

    /// Start monitoring. Returns false if Accessibility permission is missing or tap creation fails.
    /// Prompts for permission only once; logs warning at most once to avoid log spam.
    func start() -> Bool {
        // Don't prompt automatically; user grants Accessibility via Settings → Open Accessibility Settings.
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let trusted = AXIsProcessTrustedWithOptions([promptKey: false] as CFDictionary)
        guard trusted else {
            if !Self.hasLoggedAccessibilityWarning {
                Self.hasLoggedAccessibilityWarning = true
                // swiftlint:disable:next line_length - os.Logger requires a single literal (OSLogMessage)
                appLog.warning("Global shortcut (\(self.shortcut.displayString)) needs Accessibility permission. Enable Mów in System Settings → Privacy & Security → Accessibility.")
            }
            return false
        }

        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            appLog.error("Failed to create CGEventTap (check Accessibility permission)")
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runSrc = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runSrc, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        appLog.info("Global shortcut monitor started (\(self.shortcut.displayString))")
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        keyIsDown = false
        appLog.info("Global shortcut monitor stopped")
    }
}
