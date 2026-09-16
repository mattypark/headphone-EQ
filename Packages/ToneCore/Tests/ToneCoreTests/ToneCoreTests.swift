import XCTest
@testable import ToneCore

final class BiquadTests: XCTestCase {
    let sampleRate = 48_000.0

    func testPeakingHitsItsGainAtCenterFrequency() {
        for gain in [-12.0, -6, -3, 3, 6, 12] {
            let band = EQBand(type: .peaking, frequency: 1_000, gain: gain, q: 1.0)
            let measured = BiquadCoefficients(band: band, sampleRate: sampleRate)
                .magnitudeDB(at: 1_000, sampleRate: sampleRate)
            XCTAssertEqual(measured, gain, accuracy: 0.05, "peaking \(gain) dB")
        }
    }

    func testPeakingLeavesDistantFrequenciesAlone() {
        let band = EQBand(type: .peaking, frequency: 1_000, gain: 12, q: 2.0)
        let coefficients = BiquadCoefficients(band: band, sampleRate: sampleRate)
        XCTAssertEqual(coefficients.magnitudeDB(at: 50, sampleRate: sampleRate), 0, accuracy: 0.5)
        XCTAssertEqual(coefficients.magnitudeDB(at: 16_000, sampleRate: sampleRate), 0, accuracy: 0.5)
    }

    func testShelvesReachFullGainInTheirPassband() {
        let low = BiquadCoefficients(
            band: EQBand(type: .lowShelf, frequency: 200, gain: 6),
            sampleRate: sampleRate
        )
        XCTAssertEqual(low.magnitudeDB(at: 20, sampleRate: sampleRate), 6, accuracy: 0.3)
        XCTAssertEqual(low.magnitudeDB(at: 200, sampleRate: sampleRate), 3, accuracy: 0.3)
        XCTAssertEqual(low.magnitudeDB(at: 10_000, sampleRate: sampleRate), 0, accuracy: 0.3)

        let high = BiquadCoefficients(
            band: EQBand(type: .highShelf, frequency: 4_000, gain: -6),
            sampleRate: sampleRate
        )
        XCTAssertEqual(high.magnitudeDB(at: 18_000, sampleRate: sampleRate), -6, accuracy: 0.4)
        XCTAssertEqual(high.magnitudeDB(at: 100, sampleRate: sampleRate), 0, accuracy: 0.3)
    }

    func testEveryPresetIsStable() {
        for preset in Presets.all {
            for band in preset.activeBands {
                let coefficients = BiquadCoefficients(band: band, sampleRate: sampleRate)
                XCTAssertTrue(
                    coefficients.isStable,
                    "\(preset.name) band at \(band.frequency) Hz is unstable"
                )
            }
        }
    }

    func testBandsAboveNyquistDegradeToPassthrough() {
        let band = EQBand(type: .peaking, frequency: 30_000, gain: 12)
        XCTAssertEqual(BiquadCoefficients(band: band, sampleRate: sampleRate), .identity)
    }
}

final class HeadroomTests: XCTestCase {
    let sampleRate = 48_000.0

    func testBoostingProducesNegativePreamp() {
        let preamp = Headroom.preampDB(for: Presets.bassBoost, sampleRate: sampleRate)
        XCTAssertLessThan(preamp, 0)
        // Bass Boost peaks at +6 dB, so the preamp should sit just below -6.
        XCTAssertEqual(preamp, -6.3, accuracy: 0.6)
    }

    func testCutOnlyProfileKeepsFullVolume() {
        let profile = EQProfile(
            name: "Cut only",
            bands: [EQBand(type: .peaking, frequency: 1_000, gain: -6, q: 1)]
        )
        XCTAssertEqual(Headroom.preampDB(for: profile, sampleRate: sampleRate), 0, accuracy: 0.01)
    }

    func testFlatProfileNeedsNoPreamp() {
        XCTAssertEqual(Headroom.preampDB(for: .flat(), sampleRate: sampleRate), 0, accuracy: 0.01)
    }
}

final class EQEngineTests: XCTestCase {
    let sampleRate = 48_000.0
    let blockSize = 512

    /// Level of the measurement impulse. Deliberately well under the limiter's 0.85
    /// threshold — a full-scale impulse gets soft-clipped on the way through and the
    /// "measured" response is then the limiter's curve, not the EQ's.
    private static let probeAmplitude: Float = 0.2

    /// Runs an impulse through the engine and returns its response, so the measured
    /// curve can be compared against what the sliders claim.
    private func impulseResponse(
        profile: EQProfile,
        length: Int = 1 << 16
    ) -> [Float] {
        let engine = EQEngine(sampleRate: sampleRate, channelCount: 1)
        engine.prepare(sampleRate: sampleRate, channelCount: 1)
        engine.setProfile(profile, sampleRate: sampleRate)

        // Let the parameter glide settle before measuring, so we measure the profile
        // and not the ramp into it.
        for _ in 0 ..< 200 { engine.beginBlock() }

        var signal = [Float](repeating: 0, count: length)
        signal[0] = Self.probeAmplitude

        signal.withUnsafeMutableBufferPointer { buffer in
            var offset = 0
            while offset < length {
                let frames = min(blockSize, length - offset)
                engine.beginBlock()
                engine.process(buffer.baseAddress! + offset, frameCount: frames, channel: 0)
                offset += frames
            }
        }
        return signal
    }

    /// Goertzel — magnitude of one frequency bin, in dB.
    private func magnitudeDB(of signal: [Float], at frequency: Double) -> Double {
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
        let magnitude = sqrt(real * real + imaginary * imaginary)
        // Normalize out the probe level so the result reads as filter gain in dB.
        return 20 * log10(max(magnitude, 1e-12)) - 20 * log10(Double(Self.probeAmplitude))
    }

    func testMeasuredResponseMatchesTheSliders() throws {
        // Manual preamp of 0 so the measurement shows the EQ curve alone.
        let profile = EQProfile(
            name: "Test",
            bands: [
                EQBand(type: .lowShelf, frequency: 100, gain: 8, q: 0.707),
                EQBand(type: .peaking, frequency: 1_000, gain: -6, q: 1.0),
                EQBand(type: .peaking, frequency: 6_000, gain: 5, q: 1.5),
            ],
            preampMode: .manual,
            manualPreamp: 0
        )

        let response = impulseResponse(profile: profile)

        for frequency in [40.0, 100, 500, 1_000, 3_000, 6_000, 12_000] {
            let measured = magnitudeDB(of: response, at: frequency)
            let expected = Headroom.magnitudeDB(
                of: profile, at: frequency, sampleRate: sampleRate
            )
            XCTAssertEqual(
                measured, expected, accuracy: 0.1,
                "at \(Int(frequency)) Hz the engine produced \(measured) dB but the profile promises \(expected) dB"
            )
        }
    }

    func testBassSliderActuallyMovesBass() {
        let profile = EQProfile(
            name: "Bass +8",
            bands: [EQBand(type: .lowShelf, frequency: 80, gain: 8)],
            preampMode: .manual,
            manualPreamp: 0
        )
        let response = impulseResponse(profile: profile)

        // A 0.707-Q shelf is still climbing an octave below its corner, so compare
        // against the curve the profile actually describes rather than the end gain.
        XCTAssertEqual(
            magnitudeDB(of: response, at: 40),
            Headroom.magnitudeDB(of: profile, at: 40, sampleRate: sampleRate),
            accuracy: 0.1
        )
        // Deep enough into the shelf, it does reach the full 8 dB the slider promises.
        XCTAssertEqual(magnitudeDB(of: response, at: 15), 8, accuracy: 0.3)
        // And the top end is left alone.
        XCTAssertEqual(magnitudeDB(of: response, at: 8_000), 0, accuracy: 0.2)
    }

    func testSilenceStaysSilent() {
        let engine = EQEngine(sampleRate: sampleRate, channelCount: 2)
        engine.setProfile(Presets.bassBoost, sampleRate: sampleRate)

        var silence = [Float](repeating: 0, count: blockSize)
        silence.withUnsafeMutableBufferPointer { buffer in
            for _ in 0 ..< 20 {
                engine.beginBlock()
                engine.process(buffer.baseAddress!, frameCount: blockSize, channel: 0)
            }
        }
        XCTAssertTrue(silence.allSatisfy { $0 == 0 })
    }

    func testAutomaticPreampKeepsFullScaleAudioBelowClipping() {
        let engine = EQEngine(sampleRate: sampleRate, channelCount: 1)
        engine.setProfile(Presets.deepBass, sampleRate: sampleRate)
        for _ in 0 ..< 200 { engine.beginBlock() }

        // Full-scale 50 Hz sine — squarely inside the region Deep Bass boosts hardest.
        let length = 48_000
        var signal = (0 ..< length).map {
            Float(sin(2 * Double.pi * 50 * Double($0) / sampleRate))
        }

        signal.withUnsafeMutableBufferPointer { buffer in
            var offset = 0
            while offset < length {
                let frames = min(blockSize, length - offset)
                engine.beginBlock()
                engine.process(buffer.baseAddress! + offset, frameCount: frames, channel: 0)
                offset += frames
            }
        }

        let peak = signal.map(abs).max() ?? 0
        XCTAssertLessThanOrEqual(peak, 1.0, "output clipped at \(peak)")
        XCTAssertTrue(signal.allSatisfy { $0.isFinite })
    }

    func testExtremeSettingsStayFiniteAndBounded() {
        let engine = EQEngine(sampleRate: sampleRate, channelCount: 1)
        let brutal = EQProfile(
            name: "Brutal",
            bands: EQProfile.standardFrequencies.map {
                EQBand(type: .peaking, frequency: $0, gain: 24, q: 6)
            },
            preampMode: .manual,
            manualPreamp: 0   // deliberately no headroom: the limiter must carry it
        )
        engine.setProfile(brutal, sampleRate: sampleRate)
        for _ in 0 ..< 200 { engine.beginBlock() }

        var signal = (0 ..< 24_000).map { _ in Float.random(in: -1 ... 1) }
        signal.withUnsafeMutableBufferPointer { buffer in
            var offset = 0
            while offset < buffer.count {
                let frames = min(blockSize, buffer.count - offset)
                engine.beginBlock()
                engine.process(buffer.baseAddress! + offset, frameCount: frames, channel: 0)
                offset += frames
            }
        }

        XCTAssertTrue(signal.allSatisfy { $0.isFinite }, "engine produced NaN or infinity")
        XCTAssertLessThanOrEqual(signal.map(abs).max() ?? 0, 1.0, "limiter failed to bound output")
    }

    func testChannelsAreIndependent() {
        let engine = EQEngine(sampleRate: sampleRate, channelCount: 2)
        engine.setProfile(
            EQProfile(
                name: "Boost",
                bands: [EQBand(type: .lowShelf, frequency: 100, gain: 6)],
                preampMode: .manual, manualPreamp: 0
            ),
            sampleRate: sampleRate
        )
        for _ in 0 ..< 200 { engine.beginBlock() }

        var left = [Float](repeating: 0, count: blockSize)
        var right = [Float](repeating: 0, count: blockSize)
        left[0] = 0.2   // impulse on the left only, below the limiter threshold

        engine.beginBlock()
        left.withUnsafeMutableBufferPointer { engine.process($0.baseAddress!, frameCount: blockSize, channel: 0) }
        right.withUnsafeMutableBufferPointer { engine.process($0.baseAddress!, frameCount: blockSize, channel: 1) }

        XCTAssertTrue(right.allSatisfy { $0 == 0 }, "left channel bled into right")
        XCTAssertNotEqual(left[10], 0, "left channel produced no filter tail")
    }
}

final class AutoEQImportTests: XCTestCase {
    func testParsesAnAutoEQExport() throws {
        let text = """
        Preamp: -6.8 dB
        Filter 1: ON LSC Fc 105 Hz Gain 5.5 dB Q 0.70
        Filter 2: ON PK Fc 1050 Hz Gain -2.2 dB Q 1.20
        Filter 3: OFF PK Fc 3000 Hz Gain 9.9 dB Q 1.00
        Filter 4: ON HSC Fc 10000 Hz Gain 1.5 dB Q 0.70
        """

        let profile = try AutoEQImport.profile(from: text, name: "WH-1000XM4")

        XCTAssertEqual(profile.name, "WH-1000XM4")
        XCTAssertEqual(profile.bands.count, 3, "disabled filters must be skipped")
        XCTAssertEqual(profile.preampMode, .manual)
        XCTAssertEqual(profile.manualPreamp, -6.8, accuracy: 0.001)

        XCTAssertEqual(profile.bands[0].type, .lowShelf)
        XCTAssertEqual(profile.bands[0].frequency, 105, accuracy: 0.001)
        XCTAssertEqual(profile.bands[0].gain, 5.5, accuracy: 0.001)

        XCTAssertEqual(profile.bands[1].type, .peaking)
        XCTAssertEqual(profile.bands[1].gain, -2.2, accuracy: 0.001)
        XCTAssertEqual(profile.bands[2].type, .highShelf)
    }

    func testRejectsSomethingThatIsNotAnExport() {
        XCTAssertThrowsError(try AutoEQImport.profile(from: "hello world", name: "x"))
    }
}

final class EQProfileTests: XCTestCase {
    func testProfileSurvivesARoundTripThroughJSON() throws {
        let original = Presets.bassBoost
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(EQProfile.self, from: data)
        XCTAssertEqual(original, restored)
    }

    func testDisabledBandsAreExcluded() {
        var profile = EQProfile.flat()
        profile.bands[0].isEnabled = false
        XCTAssertEqual(profile.activeBands.count, profile.bands.count - 1)
    }
}
