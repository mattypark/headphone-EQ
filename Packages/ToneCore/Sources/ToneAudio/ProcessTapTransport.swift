import AudioToolbox
import CoreAudio
import Foundation
import os.lock
import ToneCore

/// System-wide EQ with nothing to install.
///
/// Uses the Core Audio process tap API (macOS 14.2+): tap everything the machine is
/// playing, mute the original path, run it through the equaliser, and hand it to the
/// real output device. An aggregate device ties the two ends together — the tap is its
/// input, the headphone is its output.
///
/// Two things learned the hard way and encoded here:
/// - the tap must exclude this process, or it hears its own output;
/// - `AVAudioEngine` cannot be retargeted onto a tap-backed aggregate device, so the
///   work happens in a raw `AudioDeviceIOProc` block.
public final class ProcessTapTransport: AudioTransport, @unchecked Sendable {
    private let engine = EQEngine()

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var tapUUID = UUID()

    public private(set) var isRunning = false
    public private(set) var latencyMilliseconds: Double = 0
    /// Name of the device audio is being sent to, for the UI.
    public private(set) var outputDeviceName: String = "—"

    /// Scratch space for de-interleaving, allocated once at start.
    private var scratch: [Float] = []
    private var maxFramesPerBlock = 4_096

    /// Optional post-EQ capture, used by `eqcli --measure` to prove the pipeline does
    /// what the profile says. Preallocated so the audio thread never allocates.
    private var captureBuffer: [Float] = []
    private var captureCount = 0
    private var isCapturing = false

    public init() {}

    deinit { stop() }

    // MARK: - Lifecycle

    public func start() throws {
        guard !isRunning else { return }

        guard let outputDevice = CA.defaultOutputDevice,
              let outputUID = CA.deviceUID(outputDevice)
        else { throw TransportError.noOutputDevice }

        outputDeviceName = CA.deviceName(outputDevice) ?? "Output"
        let sampleRate = CA.nominalSampleRate(outputDevice)
        let bufferFrames = CA.bufferFrameSize(outputDevice)

        try createTap()
        try createAggregateDevice(outputUID: outputUID)

        let format = CA.tapFormat(tapID)
        let channels = Int(format?.mChannelsPerFrame ?? 2)
        engine.prepare(sampleRate: format?.mSampleRate ?? sampleRate, channelCount: channels)

        maxFramesPerBlock = max(Int(bufferFrames) * 4, 4_096)
        scratch = [Float](repeating: 0, count: maxFramesPerBlock * EQEngine.maxChannels)

        try installIOProc()

        let status = AudioDeviceStart(aggregateID, ioProcID)
        guard status == noErr else {
            stop()
            throw TransportError.startFailed(status)
        }

        // One buffer in, one buffer out.
        latencyMilliseconds = Double(bufferFrames) / sampleRate * 2 * 1_000
        isRunning = true
    }

    public func stop() {
        if let ioProcID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        ioProcID = nil

        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        isRunning = false
    }

    public func setProfile(_ profile: EQProfile) {
        engine.setProfile(profile)
    }

    // MARK: - Setup

    private func createTap() throws {
        // Exclude ourselves, otherwise the tap captures the audio we just wrote.
        var excluded: [AudioObjectID] = []
        if let selfObject = CA.processObjectID(pid: getpid()) {
            excluded.append(selfObject)
        }

        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: excluded)
        tapUUID = UUID()
        description.uuid = tapUUID
        description.name = "headphone-EQ"
        description.isPrivate = true
        // The original path must be silenced or the untreated sound plays alongside
        // the processed one.
        description.muteBehavior = CATapMuteBehavior.mutedWhenTapped

        let status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr, tapID != kAudioObjectUnknown else {
            throw TransportError.tapCreationFailed(status)
        }
    }

    private func createAggregateDevice(outputUID: String) throws {
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "headphone-EQ Output",
            kAudioAggregateDeviceUIDKey: "com.matthewpark.headphoneeq.aggregate",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID],
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapUUID.uuidString,
                ],
            ],
        ]

        let status = AudioHardwareCreateAggregateDevice(
            description as CFDictionary, &aggregateID
        )
        guard status == noErr, aggregateID != kAudioObjectUnknown else {
            throw TransportError.aggregateCreationFailed(status)
        }
    }

    private func installIOProc() throws {
        let queue = DispatchQueue(label: "com.matthewpark.headphoneeq.io", qos: .userInteractive)
        var procID: AudioDeviceIOProcID?

        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) {
            [weak self] _, inputData, _, outputData, _ in
            self?.render(input: inputData, output: outputData)
        }
        guard status == noErr, let procID else { throw TransportError.ioProcFailed(status) }
        ioProcID = procID
    }

    // MARK: - Audio thread

    private func render(
        input: UnsafePointer<AudioBufferList>,
        output: UnsafeMutablePointer<AudioBufferList>
    ) {
        let inputBuffers = UnsafeBufferPointer(
            start: withUnsafePointer(to: input.pointee.mBuffers) { $0 },
            count: Int(input.pointee.mNumberBuffers)
        )
        let outputList = UnsafeMutableAudioBufferListPointer(output)
        guard inputBuffers.count > 0, outputList.count > 0 else { return }

        engine.beginBlock()

        // Non-interleaved is the normal case: one buffer per channel on both sides.
        if inputBuffers.count > 1 || inputBuffers[0].mNumberChannels == 1 {
            let channels = min(inputBuffers.count, outputList.count)
            for channel in 0 ..< channels {
                let source = inputBuffers[channel]
                var destination = outputList[channel]
                guard let sourceData = source.mData, let destinationData = destination.mData
                else { continue }

                let frames = Int(min(source.mDataByteSize, destination.mDataByteSize)) / MemoryLayout<Float>.size
                let samples = destinationData.assumingMemoryBound(to: Float.self)
                memcpy(destinationData, sourceData, frames * MemoryLayout<Float>.size)
                engine.process(samples, frameCount: frames, channel: channel)
                capture(samples, frameCount: frames, channel: channel)
                destination.mDataByteSize = UInt32(frames * MemoryLayout<Float>.size)
            }
            // Any output channel the tap did not fill must be silenced, or it plays
            // whatever the last block left behind.
            if outputList.count > channels {
                for channel in channels ..< outputList.count {
                    if let data = outputList[channel].mData {
                        memset(data, 0, Int(outputList[channel].mDataByteSize))
                    }
                }
            }
            return
        }

        // Interleaved fallback: de-interleave into scratch, process, put it back.
        let source = inputBuffers[0]
        var destination = outputList[0]
        guard let sourceData = source.mData, let destinationData = destination.mData else { return }

        let channels = min(Int(source.mNumberChannels), EQEngine.maxChannels)
        guard channels > 0 else { return }
        let totalSamples = Int(min(source.mDataByteSize, destination.mDataByteSize)) / MemoryLayout<Float>.size
        let frames = min(totalSamples / channels, maxFramesPerBlock)

        let input = sourceData.assumingMemoryBound(to: Float.self)
        let outputSamples = destinationData.assumingMemoryBound(to: Float.self)

        scratch.withUnsafeMutableBufferPointer { scratch in
            guard let base = scratch.baseAddress else { return }
            for channel in 0 ..< channels {
                let plane = base + channel * maxFramesPerBlock
                for frame in 0 ..< frames { plane[frame] = input[frame * channels + channel] }
                engine.process(plane, frameCount: frames, channel: channel)
                capture(plane, frameCount: frames, channel: channel)
                for frame in 0 ..< frames { outputSamples[frame * channels + channel] = plane[frame] }
            }
        }
        destination.mDataByteSize = UInt32(frames * channels * MemoryLayout<Float>.size)
    }

    // MARK: - Measurement capture

    /// Start recording post-EQ audio into a fixed buffer. Measurement only.
    public func beginCapture(seconds: Double, sampleRate: Double) {
        captureBuffer = [Float](repeating: 0, count: Int(seconds * sampleRate))
        captureCount = 0
        isCapturing = true
    }

    public func endCapture() -> [Float] {
        isCapturing = false
        return Array(captureBuffer.prefix(captureCount))
    }

    /// Left channel only — enough to measure a frequency response.
    private func capture(_ samples: UnsafePointer<Float>, frameCount: Int, channel: Int) {
        // Written only from the audio thread; begin/end are sequenced around it by the
        // caller. A measurement tool does not need more synchronisation than that.
        guard isCapturing, channel == 0 else { return }
        let writable = min(frameCount, captureBuffer.count - captureCount)
        guard writable > 0 else { return }
        captureBuffer.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            memcpy(base + captureCount, samples, writable * MemoryLayout<Float>.size)
        }
        captureCount += writable
    }
}
