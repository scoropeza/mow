//
//  AudioCaptureService.swift
//  mow
//
//  Captures microphone audio via AVFoundation for speech-to-text.
//  Outputs 16 kHz mono Float32 buffers (FluidAudio/CoreML compatible).
//

import AVFoundation
import Foundation
import os

/// Sample rate and format expected by FluidAudio ASR.
enum AudioCaptureConstants {
    static let sampleRate: Double = 16_000
    static let channelCount: AVAudioChannelCount = 1
    /// Larger buffer = fewer tap callbacks/sec, less real-time overload (2048→~23/sec, 4096→~12/sec at 48 kHz).
    static let tapBufferSize: AVAudioFrameCount = 4096
    static let tapBufferPoolCount = 4
}

/// Callback for captured audio: 16 kHz mono Float32 samples.
typealias AudioSamplesHandler = ([Float]) -> Void

/// Completion when buffered capture stops: full recording as 16 kHz mono Float32 (FluidAudio-compatible).
typealias BufferedCaptureCompletion = ([Float]) -> Void

/// Captures audio from the default microphone and delivers 16 kHz mono Float32 samples.
/// Tap runs at native format; we copy the buffer in the tap, then convert to 16 kHz on a background queue.
final class AudioCaptureService: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "com.daedalus-labs.mow.audio-capture", qos: .userInitiated)
    private var isRunning = false
    private var samplesHandler: AudioSamplesHandler?
    private let bufferLock = NSLock()
    private var accumulatedBuffer: [Float] = []
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    /// Pre-allocated buffers for the tap; no allocation on the real-time thread.
    private var bufferPool: [AVAudioPCMBuffer] = []
    private var availablePoolIndices: [Int] = []
    private let poolLock = NSLock()

    /// Target format for STT: 16 kHz mono Float32 (FluidAudio-compatible).
    private static var sttFormat: AVAudioFormat? {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: AudioCaptureConstants.sampleRate,
            channels: AudioCaptureConstants.channelCount,
            interleaved: false
        )
    }

    /// Start capturing and accumulate all samples into one buffer until stop. For press-and-hold dictation.
    /// Call stopCaptureBuffered(completion:) to get the full 16 kHz mono Float32 buffer (FluidAudio-compatible).
    func startCaptureBuffered() throws {
        bufferLock.lock()
        accumulatedBuffer.removeAll(keepingCapacity: true)
        bufferLock.unlock()
        try startCapture { [weak self] samples in
            self?.bufferLock.lock()
            self?.accumulatedBuffer.append(contentsOf: samples)
            self?.bufferLock.unlock()
        }
    }

    /// Stop capturing and return the accumulated buffer (16 kHz mono Float32). Completion called on main queue.
    func stopCaptureBuffered(completion: @escaping BufferedCaptureCompletion) {
        bufferLock.lock()
        let buffer = accumulatedBuffer
        accumulatedBuffer.removeAll(keepingCapacity: true)
        bufferLock.unlock()
        stopCapture()
        DispatchQueue.main.async {
            completion(buffer)
        }
    }

    /// Start capturing from the default input. Tap only copies the buffer; conversion on a background queue
    /// to avoid "skipping cycle due to overload".
    func startCapture(handler: @escaping AudioSamplesHandler) throws {
        guard !isRunning else {
            audioLog.warning("Audio capture already running")
            return
        }

        guard AVCaptureDevice.default(for: .audio) != nil else {
            audioLog.error("No audio input device available")
            throw AudioCaptureError.noInputAvailable
        }

        let inputNode = engine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)
        guard let target = Self.sttFormat else {
            throw AudioCaptureError.formatCreationFailed
        }
        guard let conv = AVAudioConverter(from: nativeFormat, to: target) else {
            audioLog.error("Cannot create converter from \(nativeFormat.sampleRate) Hz to \(target.sampleRate) Hz")
            throw AudioCaptureError.formatCreationFailed
        }

        samplesHandler = handler
        converter = conv
        targetFormat = target

        // Pre-allocate buffer pool so the tap never allocates (avoids real-time overload).
        bufferPool = (0..<AudioCaptureConstants.tapBufferPoolCount).compactMap { _ in
            AVAudioPCMBuffer(pcmFormat: nativeFormat, frameCapacity: AudioCaptureConstants.tapBufferSize)
        }
        availablePoolIndices = Array(0..<bufferPool.count)

        inputNode.installTap(
            onBus: 0,
            bufferSize: AudioCaptureConstants.tapBufferSize,
            format: nativeFormat
        ) { [weak self] buffer, _ in
            self?.enqueueBufferCopy(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            converter = nil
            targetFormat = nil
            bufferPool = []
            availablePoolIndices = []
            throw AudioCaptureError.engineStartFailed(error)
        }
        isRunning = true
        audioLog.info("Audio capture started (native \(Int(nativeFormat.sampleRate)) Hz → 16 kHz)")
    }

    /// Stop capturing and remove the tap. Safe to call from any thread.
    func stopCapture() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        samplesHandler = nil
        converter = nil
        targetFormat = nil
        bufferPool = []
        availablePoolIndices = []
        audioLog.info("Audio capture stopped")
    }

    /// Called on the real-time tap thread: no allocation, only copy into a pre-allocated pool buffer and enqueue.
    private func enqueueBufferCopy(_ buffer: AVAudioPCMBuffer) {
        let frameLength = buffer.frameLength
        guard frameLength > 0 else { return }
        poolLock.lock()
        guard let index = availablePoolIndices.popLast() else {
            poolLock.unlock()
            return
        }
        poolLock.unlock()
        let poolBuffer = bufferPool[index]
        let copyFrames = min(frameLength, poolBuffer.frameCapacity)
        poolBuffer.frameLength = copyFrames
        guard copyFrames > 0, let src = buffer.floatChannelData, let dst = poolBuffer.floatChannelData else { return }
        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(copyFrames)
        for ch in 0..<channelCount {
            memcpy(dst[ch], src[ch], frameCount * MemoryLayout<Float>.size)
        }
        queue.async { [weak self] in
            self?.processBuffer(poolBuffer)
            self?.poolLock.lock()
            self?.availablePoolIndices.append(index)
            self?.poolLock.unlock()
        }
    }

    /// Runs on our queue: convert to 16 kHz and deliver to handler.
    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let conv = converter, let target = targetFormat else { return }
        let inputFrameCount = buffer.frameLength
        let ratio = target.sampleRate / buffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(inputFrameCount) * ratio + 1)
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: target,
            frameCapacity: max(outputFrameCapacity, 1)
        ) else { return }
        outputBuffer.frameLength = 0

        var hasProvidedInput = false
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if !hasProvidedInput {
                hasProvidedInput = true
                outStatus.pointee = .haveData
                return buffer
            }
            outStatus.pointee = .noDataNow
            return nil
        }
        conv.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        if let error = error {
            audioLog.error("Resample error: \(error.localizedDescription)")
            return
        }
        guard outputBuffer.frameLength > 0, let channelData = outputBuffer.floatChannelData else { return }
        let frameLength = Int(outputBuffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        samplesHandler?(samples)
    }
}

enum AudioCaptureError: LocalizedError {
    case formatCreationFailed
    case engineStartFailed(Error)
    case noInputAvailable

    var errorDescription: String? {
        switch self {
        case .formatCreationFailed:
            return "Could not create 16 kHz mono audio format."
        case .engineStartFailed(let error):
            return "Audio engine failed to start: \(error.localizedDescription)"
        case .noInputAvailable:
            return "No audio input device is available."
        }
    }
}
