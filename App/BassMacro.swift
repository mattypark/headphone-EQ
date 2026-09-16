import SwiftUI
import ToneCore

/// One control for the thing people actually want.
///
/// Sony calls theirs Clear Bass. It earns its place because "more bass" is a single
/// intent and making someone express it by dragging three faders in the right ratio is
/// asking them to do the equalizer's job. This drives the three low bands directly —
/// no hidden state, no second source of truth: you can watch the faders move.
struct BassMacro: View {
    @Binding var profile: EQProfile
    let range: ClosedRange<Double>
    let onChange: () -> Void

    /// How much of the macro each low band takes. Tapering upward is what keeps a big
    /// low end from smearing into the vocals at 250 Hz.
    private static let weights: [Double] = [1.0, 0.88, 0.55, 0.18]

    private var value: Double {
        profile.bands.first?.gain ?? 0
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("BASS")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(value > 0.25 ? Theme.boost : Theme.textDim)
                .frame(width: 38, alignment: .leading)

            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.black.opacity(0.55))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
                        .frame(height: 8)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Theme.boost.opacity(0.35), Theme.boost],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, fillWidth(in: width)), height: 8)
                        .offset(x: fillOrigin(in: width))

                    Circle()
                        .fill(LinearGradient(
                            colors: [Color(white: 0.48), Color(white: 0.22)],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .overlay(Circle().strokeBorder(
                            value == 0 ? Color.white.opacity(0.2) : Theme.boost.opacity(0.8),
                            lineWidth: 1
                        ))
                        .frame(width: 18, height: 18)
                        .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
                        .offset(x: knobX(in: width))
                }
                .frame(height: 20)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { drag in
                        let fraction = min(max(drag.location.x / width, 0), 1)
                        let proposed = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
                        apply((proposed / 0.5).rounded() * 0.5)
                    }
                )
            }
            .frame(height: 20)

            Text(value == 0 ? "0" : String(format: "%+.1f", value))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(value == 0 ? Theme.textDim : Theme.boost)
                .frame(width: 34, alignment: .trailing)
        }
    }

    private func apply(_ newValue: Double) {
        for (index, weight) in Self.weights.enumerated() where index < profile.bands.count {
            let scaled = newValue * weight
            profile.bands[index].gain = min(max(scaled, range.lowerBound), range.upperBound)
        }
        onChange()
    }

    private func fraction(of value: Double) -> CGFloat {
        CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
    }

    private func knobX(in width: CGFloat) -> CGFloat {
        fraction(of: value) * (width - 18)
    }

    private func fillOrigin(in width: CGFloat) -> CGFloat {
        min(fraction(of: 0), fraction(of: value)) * width
    }

    private func fillWidth(in width: CGFloat) -> CGFloat {
        abs(fraction(of: value) - fraction(of: 0)) * width
    }
}
