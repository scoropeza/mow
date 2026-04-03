//
//  AppStatus.swift
//  mow
//
//  Application status for the menu bar indicator (green / yellow / red).
//

import Combine
import SwiftUI

enum AppStatus: Equatable {
    case permissionsNeeded  // Microphone and/or Accessibility not granted
    case loading
    case ready
    case warning            // Transient issue (short recording, quiet audio) — auto-recovers to ready
    case error              // Fatal issue (model load failure) — requires restart

    var color: Color {
        switch self {
        case .permissionsNeeded: return .purple
        case .loading: return .yellow
        case .ready: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    var isError: Bool {
        self == .error || self == .warning
    }
}
