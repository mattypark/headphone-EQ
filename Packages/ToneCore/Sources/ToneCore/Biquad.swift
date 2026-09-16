import Foundation

/// Second-order section coefficients, normalized so `a0 == 1`.
///
/// Difference equation:
/// `y[n] = b0·x[n] + b1·x[n-1] + b2·x[n-2] − a1·y[n-1] − a2·y[n-2]`
public struct BiquadCoefficients: Sendable, Equatable {
    public var b0: Double
    public var b1: Double
    public var b2: Double
    public var a1: Double
    public var a2: Double

    public static let identity = BiquadCoefficients(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)

    public init(b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
        self.b0 = b0
        self.b1 = b1
        self.b2 = b2
        self.a1 = a1
        self.a2 = a2
    }

    /// Robert Bristow-Johnson's audio EQ cookbook formulas. These are the same
    /// coefficients every mixing desk and every other equalizer uses; deviating from
    /// them is how an EQ ends up sounding subtly wrong.
    public init(band: EQBand, sampleRate: Double) {
        // A filter centered above Nyquist is meaningless — pass audio through untouched
        // rather than producing an unstable section.
        let nyquist = sampleRate / 2
        guard band.frequency > 0, band.frequency < nyquist, sampleRate > 0 else {
            self = .identity
            return
        }

        let q = max(band.q, 0.05)
        let w0 = 2 * Double.pi * band.frequency / sampleRate
        let cosW0 = cos(w0)
        let alpha = sin(w0) / (2 * q)

        switch band.type {
        case .peaking:
            let a = pow(10, band.gain / 40)
            let a0 = 1 + alpha / a
            self.init(
                b0: (1 + alpha * a) / a0,
                b1: (-2 * cosW0) / a0,
                b2: (1 - alpha * a) / a0,
                a1: (-2 * cosW0) / a0,
                a2: (1 - alpha / a) / a0
            )

        case .lowShelf:
            let a = pow(10, band.gain / 40)
            let sqrtA = sqrt(a)
            let a0 = (a + 1) + (a - 1) * cosW0 + 2 * sqrtA * alpha
            self.init(
                b0: (a * ((a + 1) - (a - 1) * cosW0 + 2 * sqrtA * alpha)) / a0,
                b1: (2 * a * ((a - 1) - (a + 1) * cosW0)) / a0,
                b2: (a * ((a + 1) - (a - 1) * cosW0 - 2 * sqrtA * alpha)) / a0,
                a1: (-2 * ((a - 1) + (a + 1) * cosW0)) / a0,
                a2: ((a + 1) + (a - 1) * cosW0 - 2 * sqrtA * alpha) / a0
            )

        case .highShelf:
            let a = pow(10, band.gain / 40)
            let sqrtA = sqrt(a)
            let a0 = (a + 1) - (a - 1) * cosW0 + 2 * sqrtA * alpha
            self.init(
                b0: (a * ((a + 1) + (a - 1) * cosW0 + 2 * sqrtA * alpha)) / a0,
                b1: (-2 * a * ((a - 1) + (a + 1) * cosW0)) / a0,
                b2: (a * ((a + 1) + (a - 1) * cosW0 - 2 * sqrtA * alpha)) / a0,
                a1: (2 * ((a - 1) - (a + 1) * cosW0)) / a0,
                a2: ((a + 1) - (a - 1) * cosW0 - 2 * sqrtA * alpha) / a0
            )

        case .highPass:
            let a0 = 1 + alpha
            self.init(
                b0: ((1 + cosW0) / 2) / a0,
                b1: (-(1 + cosW0)) / a0,
                b2: ((1 + cosW0) / 2) / a0,
                a1: (-2 * cosW0) / a0,
                a2: (1 - alpha) / a0
            )

        case .lowPass:
            let a0 = 1 + alpha
            self.init(
                b0: ((1 - cosW0) / 2) / a0,
                b1: (1 - cosW0) / a0,
                b2: ((1 - cosW0) / 2) / a0,
                a1: (-2 * cosW0) / a0,
                a2: (1 - alpha) / a0
            )
        }
    }

    /// Magnitude of this section at `frequency`, in dB.
    ///
    /// Used both by the tests (to prove a slider does what it says) and by the headroom
    /// calculation (to know how far to duck the preamp).
    public func magnitudeDB(at frequency: Double, sampleRate: Double) -> Double {
        let w = 2 * Double.pi * frequency / sampleRate
        let cosW = cos(w), sinW = sin(w)
        let cos2W = cos(2 * w), sin2W = sin(2 * w)

        let numeratorReal = b0 + b1 * cosW + b2 * cos2W
        let numeratorImag = -(b1 * sinW + b2 * sin2W)
        let denominatorReal = 1 + a1 * cosW + a2 * cos2W
        let denominatorImag = -(a1 * sinW + a2 * sin2W)

        let numeratorMagnitude = sqrt(numeratorReal * numeratorReal + numeratorImag * numeratorImag)
        let denominatorMagnitude = sqrt(denominatorReal * denominatorReal + denominatorImag * denominatorImag)
        guard denominatorMagnitude > 0 else { return 0 }

        return 20 * log10(max(numeratorMagnitude / denominatorMagnitude, 1e-12))
    }

    /// True when the section's poles sit inside the unit circle.
    public var isStable: Bool {
        abs(a2) < 1 && abs(a1) < 1 + a2
    }
}
