import Foundation

/// Works out how far the signal must be turned down before EQ is applied so that
/// boosting bass cannot push the output past full scale.
///
/// This is the difference between an equalizer that sounds better and one that just
/// sounds louder and then crackles.
public enum Headroom {
    /// Log-spaced probe points from 20 Hz to 20 kHz. Dense enough that a narrow
    /// resonance cannot hide between two probes.
    static func probeFrequencies(sampleRate: Double, count: Int = 512) -> [Double] {
        let low = 20.0
        let high = min(20_000, sampleRate / 2 * 0.99)
        guard high > low, count > 1 else { return [low] }

        let ratio = log(high / low)
        return (0 ..< count).map { low * exp(ratio * Double($0) / Double(count - 1)) }
    }

    /// Combined magnitude of every enabled band at `frequency`, in dB.
    public static func magnitudeDB(
        of profile: EQProfile,
        at frequency: Double,
        sampleRate: Double
    ) -> Double {
        profile.activeBands.reduce(0) { total, band in
            total + BiquadCoefficients(band: band, sampleRate: sampleRate)
                .magnitudeDB(at: frequency, sampleRate: sampleRate)
        }
    }

    /// The loudest point of the profile's response curve, in dB.
    public static func peakGainDB(of profile: EQProfile, sampleRate: Double) -> Double {
        let coefficients = profile.activeBands.map {
            BiquadCoefficients(band: $0, sampleRate: sampleRate)
        }
        guard !coefficients.isEmpty else { return 0 }

        return probeFrequencies(sampleRate: sampleRate).reduce(-.infinity) { peak, frequency in
            let total = coefficients.reduce(0) {
                $0 + $1.magnitudeDB(at: frequency, sampleRate: sampleRate)
            }
            return max(peak, total)
        }
    }

    /// Preamp in dB for a profile — negative when the profile boosts anything.
    public static func preampDB(for profile: EQProfile, sampleRate: Double) -> Double {
        switch profile.preampMode {
        case .manual:
            return profile.manualPreamp
        case .automatic:
            // A hair of extra room, because inter-sample peaks sit slightly above
            // anything a per-sample measurement can see.
            let peak = peakGainDB(of: profile, sampleRate: sampleRate)
            return peak > 0 ? -(peak + 0.3) : 0
        }
    }
}
