import SwiftUI
import ToneCore

/// The frequency response drawn from the same maths the audio thread runs, so the
/// picture and the sound cannot disagree.
struct ResponseCurve: View {
    let profile: EQProfile
    let range: ClosedRange<Double>

    var body: some View {
        Canvas { context, size in
            let sampleRate = 48_000.0
            let low = 20.0, high = 20_000.0
            let steps = max(Int(size.width), 2)

            var path = Path()
            for step in 0 ..< steps {
                let fraction = Double(step) / Double(steps - 1)
                let frequency = low * pow(high / low, fraction)
                let gain = Headroom.magnitudeDB(of: profile, at: frequency, sampleRate: sampleRate)
                let clamped = min(max(gain, range.lowerBound), range.upperBound)
                let y = size.height * (1 - (clamped - range.lowerBound) / (range.upperBound - range.lowerBound))
                let point = CGPoint(x: size.width * fraction, y: y)
                step == 0 ? path.move(to: point) : path.addLine(to: point)
            }

            // Center line first, so the curve reads as a deviation from flat.
            var zero = Path()
            zero.move(to: CGPoint(x: 0, y: size.height / 2))
            zero.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(zero, with: .color(Theme.hairline.opacity(2)), lineWidth: 1)

            // Fill under the curve, tinted by which way it is going overall.
            var fill = path
            fill.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            fill.addLine(to: CGPoint(x: 0, y: size.height / 2))
            fill.closeSubpath()
            context.fill(
                fill,
                with: .linearGradient(
                    Gradient(colors: [Theme.boost.opacity(0.22), Theme.cut.opacity(0.10)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )

            context.stroke(path, with: .color(Theme.text.opacity(0.85)), lineWidth: 1.5)
        }
        .drawingGroup()
    }
}
