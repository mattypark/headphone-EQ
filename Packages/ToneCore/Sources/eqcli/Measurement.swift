import Foundation
import ToneAudio
import ToneCore

/// Proves the pipeline applies the curve it claims.
///
/// The trick is measuring twice. Absolute levels depend on the track, the device, the
/// volume and the room; the *difference* between a flat pass and a preset pass depends
/// on nothing but the equaliser. Same signal both times, so the comparison is exact.
enum Measurement {
    static let sampleRate = 48_000.0

    static func run(profile: EQProfile, seconds: Double) throws {
        let signalURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("headphone-eq-test-signal.wav")
        try writeTestSignal(to: signalURL, seconds: seconds + 1)

        print("measuring '\(profile.name)' — two passes of \(Int(seconds))s")
        print("(system audio will play the test signal; leave the volume alone between passes)\n")

        let flatCapture = try capture(profile: .flat(), signal: signalURL, seconds: seconds)
        let presetCapture = try capture(profile: profile, signal: signalURL, seconds: seconds)

        guard flatCapture.count > Int(sampleRate), presetCapture.count > Int(sampleRate) else {
            print("captured too little audio — is anything actually playing?")
            return
        }

        // A profile's own preamp is part of what it does, so compare against the full
        // curve including it.
        let preamp = Headroom.preampDB(for: profile, sampleRate: sampleRate)

        print("      freq    measured    expected   delta")
        var worst = 0.0
        for frequency in EQProfile.standardFrequencies where frequency < sampleRate / 2 {
            let flat = energyDB(flatCapture, at: frequency)
            let shaped = energyDB(presetCapture, at: frequency)
            let measured = shaped - flat
            let expected = Headroom.magnitudeDB(of: profile, at: frequency, sampleRate: sampleRate) + preamp
            let delta = measured - expected
            worst = max(worst, abs(delta))
            print(String(format: "%8.0f Hz  %+8.2f dB  %+8.2f dB  %+6.2f", frequency, measured, expected, delta))
        }
        print(String(format: "\nworst deviation: %.2f dB", worst))
        print(worst < 1.5 ? "PASS — the pipeline renders the profile it was given" : "FAIL — measured curve does not match the profile")
    }

    private static func capture(profile: EQProfile, signal: URL, seconds: Double) throws -> [Float] {
        let transport = ProcessTapTransport()
        transport.setProfile(profile)
        try transport.start()
        defer { transport.stop() }

        // Let the parameter glide settle before the capture window opens.
        Thread.sleep(forTimeInterval: 0.4)

        let player = Process()
        player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        player.arguments = [signal.path]
        try player.run()

        Thread.sleep(forTimeInterval: 0.3)
        transport.beginCapture(seconds: seconds, sampleRate: sampleRate)
        Thread.sleep(forTimeInterval: seconds)
        let samples = transport.endCapture()

        player.terminate()
        player.waitUntilExit()
        print("  \(profile.name): captured \(samples.count) frames")
        return samples
    }

    /// Goertzel magnitude at one frequency, in dB.
    static func energyDB(_ signal: [Float], at frequency: Double) -> Double {
        let omega = 2 * Double.pi * frequency / sampleRate
        let coefficient = 2 * cos(omega)
        var s1 = 0.0, s2 = 0.0
        for sample in signal {
            let s0 = Double(sample) + coefficient * s1 - s2
            s2 = s1
            s1 = s0
        }
        let real = s1 - s2 * cos(omega)
        let imaginary = s2 * sin(omega)
        return 20 * log10(max(sqrt(real * real + imaginary * imaginary), 1e-12))
    }

    /// A steady multitone: one sine at each frequency we measure.
    ///
    /// Pink noise was the obvious choice and the wrong one — a single-bin Goertzel on
    /// noise measures that bin's random fluctuation, not the filter. A multitone puts
    /// deterministic energy exactly where we look, and every standard frequency is a
    /// whole multiple of the 0.25 Hz bin spacing of a four-second window, so there is
    /// no spectral leakage to correct for either.
    private static func writeTestSignal(to url: URL, seconds: Double) throws {
        let frameCount = Int(seconds * sampleRate)
        let tones = EQProfile.standardFrequencies.filter { $0 < sampleRate / 2 }
        // Headroom for the worst case where every tone peaks together.
        let amplitude = 0.7 / Double(tones.count)

        var samples = [Int16](repeating: 0, count: frameCount * 2)
        for frame in 0 ..< frameCount {
            var value = 0.0
            for (index, frequency) in tones.enumerated() {
                // Spread the phases so the tones do not all crest at once.
                let phase = Double(index) * 2 * Double.pi / Double(tones.count)
                value += amplitude * sin(2 * Double.pi * frequency * Double(frame) / sampleRate + phase)
            }
            let sample = Int16(max(-1, min(1, value)) * 20_000)
            samples[frame * 2] = sample
            samples[frame * 2 + 1] = sample
        }

        var data = Data()
        let byteCount = samples.count * MemoryLayout<Int16>.size
        func append<T>(_ value: T) { withUnsafeBytes(of: value) { data.append(contentsOf: $0) } }

        data.append(contentsOf: Array("RIFF".utf8));  append(UInt32(36 + byteCount))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8));  append(UInt32(16))
        append(UInt16(1)); append(UInt16(2))                      // PCM, stereo
        append(UInt32(sampleRate)); append(UInt32(sampleRate) * 4)
        append(UInt16(4)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8));  append(UInt32(byteCount))
        samples.withUnsafeBytes { data.append(contentsOf: $0) }

        try data.write(to: url)
    }
}
