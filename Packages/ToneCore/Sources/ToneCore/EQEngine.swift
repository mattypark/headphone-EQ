import Foundation
import os.lock

/// The real-time equalizer: a cascade of biquads per channel, plus preamp and a
/// safety limiter.
///
/// Everything the audio thread touches is preallocated. `process` performs no
/// allocation, no locking that can block, and no Swift runtime calls that could;
/// a parameter change that arrives mid-block is simply picked up on the next one.
public final class EQEngine: @unchecked Sendable {
    /// Ceiling on band count so all state can be allocated up front.
    public static let maxBands = 16
    /// Ceiling on channels — stereo today, room for surround.
    public static let maxChannels = 8

    private struct SectionState {
        var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0
    }

    private var sampleRate: Double
    private var channelCount: Int

    /// Coefficients currently in use, indexed `[section]`.
    private var coefficients: [BiquadCoefficients]
    /// Filter memory, indexed `[channel * maxBands + section]`.
    private var state: [SectionState]
    private var activeSectionCount = 0

    /// Parameters the audio thread is currently rendering, glided toward the target so
    /// dragging a slider does not produce zipper noise.
    private var smoothedGains: [Double]
    private var smoothedPreampLinear: Float = 1

    /// Target set by the UI thread, guarded by a lock the audio thread only ever *tries*.
    private let targetLock = OSAllocatedUnfairLock<Target>(initialState: Target())
    private struct Target {
        var bands: [EQBand] = []
        var preampLinear: Float = 1
        var generation: UInt64 = 0
    }
    private var appliedGeneration: UInt64 = 0
    private var bands: [EQBand] = []

    /// Above this the limiter starts bending peaks instead of letting them clip.
    ///
    /// Deliberately low with a long tanh knee, so loud bass meets gentle saturation
    /// rather than a hard ceiling. Saturation adds harmonics, and harmonics read as
    /// *more* bass, not less — the opposite of what a brickwall does.
    private let limiterThreshold: Float = 0.70

    public init(sampleRate: Double = 48_000, channelCount: Int = 2) {
        self.sampleRate = sampleRate
        self.channelCount = min(channelCount, Self.maxChannels)
        coefficients = Array(repeating: .identity, count: Self.maxBands)
        state = Array(repeating: SectionState(), count: Self.maxBands * Self.maxChannels)
        smoothedGains = Array(repeating: 0, count: Self.maxBands)
    }

    // MARK: - Control thread

    /// Point the engine at a new profile. Safe to call from the UI at slider rate.
    public func setProfile(_ profile: EQProfile, sampleRate: Double? = nil) {
        if let sampleRate, sampleRate != self.sampleRate {
            self.sampleRate = sampleRate
        }
        let rate = sampleRate ?? self.sampleRate
        let active = Array(profile.activeBands.prefix(Self.maxBands))
        let preampDB = Headroom.preampDB(for: profile, sampleRate: rate)

        targetLock.withLock { target in
            target.bands = active
            target.preampLinear = Float(pow(10, preampDB / 20))
            target.generation &+= 1
        }
    }

    /// Reconfigure for a new stream format. Call from the control thread only, while
    /// the audio thread is stopped.
    public func prepare(sampleRate: Double, channelCount: Int) {
        self.sampleRate = sampleRate
        self.channelCount = min(channelCount, Self.maxChannels)
        reset()
    }

    /// Clear filter memory — used when the output device changes underneath us, so a
    /// stale tail cannot pop into the new stream.
    public func reset() {
        for index in state.indices { state[index] = SectionState() }
    }

    // MARK: - Audio thread

    /// Process one block, one channel at a time, in place.
    ///
    /// Call `beginBlock()` once per block before the per-channel calls.
    public func beginBlock() {
        // Pick up a new target only if the lock is free. The audio thread never waits
        // on the UI thread; a missed update lands one block later and is inaudible.
        if let target = targetLock.withLockIfAvailable({ $0 }), target.generation != appliedGeneration {
            appliedGeneration = target.generation
            bands = target.bands
            activeSectionCount = target.bands.count
            pendingPreampLinear = target.preampLinear
        }

        // Glide gains and preamp toward their targets, then rebuild coefficients. This
        // costs a few dozen sin/cos per block — nothing next to the sample loop.
        var changed = false
        for index in 0 ..< activeSectionCount {
            let target = bands[index].gain
            let current = smoothedGains[index]
            if abs(target - current) > 0.0005 {
                smoothedGains[index] = current + (target - current) * Self.glide
                changed = true
            } else if smoothedGains[index] != target {
                smoothedGains[index] = target
                changed = true
            }
        }
        if changed || needsCoefficientRebuild {
            needsCoefficientRebuild = false
            for index in 0 ..< activeSectionCount {
                var band = bands[index]
                band.gain = smoothedGains[index]
                coefficients[index] = BiquadCoefficients(band: band, sampleRate: sampleRate)
            }
        }

        if abs(pendingPreampLinear - smoothedPreampLinear) > 0.0001 {
            smoothedPreampLinear += (pendingPreampLinear - smoothedPreampLinear) * Float(Self.glide)
        } else {
            smoothedPreampLinear = pendingPreampLinear
        }
    }

    private var pendingPreampLinear: Float = 1
    private var needsCoefficientRebuild = true
    /// Per-block glide coefficient. At ~128 blocks/second this settles in ~60 ms —
    /// fast enough to feel instant, slow enough to be silent.
    private static let glide = 0.25

    public func process(
        _ samples: UnsafeMutablePointer<Float>,
        frameCount: Int,
        channel: Int
    ) {
        guard channel < Self.maxChannels else { return }
        let preamp = smoothedPreampLinear
        let sections = activeSectionCount
        let base = channel * Self.maxBands

        for frame in 0 ..< frameCount {
            var sample = Double(samples[frame] * preamp)

            for section in 0 ..< sections {
                let c = coefficients[section]
                var s = state[base + section]
                let input = Float(sample)
                let output = c.b0 * Double(input)
                    + c.b1 * Double(s.x1)
                    + c.b2 * Double(s.x2)
                    - c.a1 * Double(s.y1)
                    - c.a2 * Double(s.y2)
                s.x2 = s.x1
                s.x1 = input
                s.y2 = s.y1
                s.y1 = Float(output)
                state[base + section] = s
                sample = output
            }

            samples[frame] = limit(Float(sample))
        }
    }

    /// Soft knee above `limiterThreshold`, hard-bounded at 1.0. A last line of defence:
    /// with automatic preamp it should almost never engage.
    private func limit(_ sample: Float) -> Float {
        let magnitude = abs(sample)
        guard magnitude > limiterThreshold else { return sample }
        guard magnitude.isFinite else { return 0 }

        let excess = (magnitude - limiterThreshold) / (1 - limiterThreshold)
        let shaped = limiterThreshold + (1 - limiterThreshold) * tanhf(excess)
        return sample < 0 ? -shaped : shaped
    }
}
