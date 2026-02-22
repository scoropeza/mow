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
    case error

    var color: Color {
        switch self {
        case .permissionsNeeded: return .purple
        case .loading: return .yellow
        case .ready: return .green
        case .error: return .red
        }
    }

    var isError: Bool {
        self == .error
    }
}
