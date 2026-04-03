//
//  TextInjectionService.swift
//  mow
//
//  Injects text at cursor using macOS Accessibility API (8.1); fallback: paste via clipboard (8.3).
//  Target: any text-input-capable app (8.4).
//

import AppKit
import ApplicationServices
import Foundation
import os

/// Captures the frontmost app and focused text element so injection can target them later.
struct InjectionTarget {
    let app: NSRunningApplication
    let focusedElement: AXUIElement?

    /// Capture the current frontmost app and focused element. Call from main thread before transcription.
    static func capture() -> InjectionTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef
        )
        let focused: AXUIElement? = (result == .success && focusedRef != nil)
            // swiftlint:disable:next force_cast - type verified by AX API; CFTypeRef is AXUIElement here
            ? (focusedRef as! AXUIElement)
            : nil
        return InjectionTarget(app: app, focusedElement: focused)
    }

    /// Re-activate the captured app so it regains focus before injection.
    func activate() {
        app.activate()
        // Brief yield so the app's windows come to front before we inject.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    }
}

/// Injects text into the focused text field (AX API) or via Cmd+V paste.
enum TextInjectionService {
    private static let injectionLog = Logger(subsystem: "mow", category: "TextInjection")

    /// Inject text at the focused element's cursor/selection, or paste via clipboard if AX fails.
    /// Call from main thread. Returns true if injection or paste succeeded.
    @discardableResult
    static func inject(_ text: String, target: InjectionTarget? = nil) -> Bool {
        guard !text.isEmpty else { return true }

        // Re-activate the target app if we have one (it may have lost focus during transcription).
        target?.activate()

        // Try 1: inject into the saved target element.
        if let element = target?.focusedElement, injectViaAccessibility(text, into: element) {
            return true
        }
        // Try 2: query current focus (target app is now frontmost after activate).
        if injectViaAccessibility(text) {
            return true
        }
        return injectViaClipboard(text)
    }

    // MARK: - Accessibility API (8.1)

    private static func injectViaAccessibility(_ text: String, into focused: AXUIElement? = nil) -> Bool {
        let element: AXUIElement
        if let focused {
            element = focused
        } else {
            let systemWide = AXUIElementCreateSystemWide()
            var focusedRef: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(
                systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef
            )
            guard result == .success, let focusedRef = focusedRef else {
                injectionLog.debug("AX: no focused element")
                return false
            }
            // swiftlint:disable:next force_cast - type verified by AX API; CFTypeRef is AXUIElement here
            element = (focusedRef as! AXUIElement)
        }

        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let valueRef = valueRef else {
            injectionLog.debug("AX: no value attribute")
            return false
        }
        // swiftlint:disable:next force_cast - AX value attribute returns CFString
        let currentString = valueRef as! CFString
        let current = (currentString as String)

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &rangeRef
        ) == .success,
              let rangeRef = rangeRef,
              CFGetTypeID(rangeRef) == AXValueGetTypeID() else {
            injectionLog.debug("AX: no selected text range")
            return false
        }
        // swiftlint:disable:next force_cast - type ID verified above
        let rangeValue = rangeRef as! AXValue
        var cfRange = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rangeValue, .cfRange, &cfRange) else {
            injectionLog.debug("AX: could not get range value")
            return false
        }
        let range = NSRange(location: cfRange.location, length: cfRange.length)
        guard range.location >= 0, range.location <= current.utf16.count,
              range.length >= 0, range.location + range.length <= current.utf16.count else {
            injectionLog.debug("AX: range out of bounds")
            return false
        }

        let newString = (current as NSString).replacingCharacters(in: range, with: text)
        let newValue = newString as CFString
        guard AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, newValue) == .success else {
            injectionLog.debug("AX: set value failed")
            return false
        }

        var newRange = CFRange(location: cfRange.location + (text as NSString).length, length: 0)
        if let newRangeValue = AXValueCreate(.cfRange, &newRange) {
            AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, newRangeValue)
        }
        injectionLog.info("Injected \(text.count) characters via Accessibility")
        return true
    }

    // MARK: - Clipboard fallback (8.3)

    private static func injectViaClipboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            injectionLog.error("Clipboard: setString failed")
            return false
        }
        simulateCommandV()
        injectionLog.info("Injected \(text.count) characters via clipboard (Cmd+V)")
        return true
    }

    private static func simulateCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyCode: CGKeyCode = 9 // V
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyDown?.flags = CGEventFlags.maskCommand
        keyUp?.flags = CGEventFlags.maskCommand
        keyDown?.post(tap: CGEventTapLocation.cghidEventTap)
        keyUp?.post(tap: CGEventTapLocation.cghidEventTap)
    }
}
