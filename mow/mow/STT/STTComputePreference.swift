//
//  STTComputePreference.swift
//  mow
//
//  Prefer ANE on Apple Silicon (M1/M2/M3); use Metal fallback on Intel (task 5.4).
//

import CoreML
import Foundation

enum STTComputePreference {
    /// Prefer Apple Neural Engine on M1/M2/M3; use CPU+Metal on Intel (ANE not available).
    static var preferredComputeUnits: MLComputeUnits {
        isAppleSilicon ? .cpuAndNeuralEngine : .cpuAndGPU
    }

    private static var isAppleSilicon: Bool {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        guard size > 0 else { return false }
        var machine = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.machine", &machine, &size, nil, 0) == 0 else { return false }
        return String(cString: machine).lowercased().contains("arm")
    }
}
