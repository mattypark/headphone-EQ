import SwiftUI
import ToneCore

/// One vertical fader: tick-marked track, a knob you can throw, and a live dB readout.
///
/// Drag moves it; scroll nudges it; double-click returns it to zero. The whole point of
/// a fader over a number field is that the row of them *is* the frequency response —
/// so the knob positions have to be readable at a glance.
struct BandFader: View {
    let frequency: Double
    @Binding var gain: Double
    let range: ClosedRange<Double>
    let onChange: () -> Void

    @State private var dragStartGain: Double?

    private let trackHeight: CGFloat = 132
    private let knobHeight: CGFloat = 13

    var body: some View {
        VStack(spacing: 6) {
            Text(gain == 0 ? "0" : String(format: "%+.1f", gain))
                .font(Theme.numerals)
                .foregroundStyle(gain == 0 ? Theme.textDim : Theme.tint(forGain: gain))
                .frame(height: 12)

            track

            Text(label(for: frequency))
                .font(Theme.label)
                .foregroundStyle(Theme.textDim)
                .frame(height: 12)
        }
        .frame(width: 34)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            gain = 0
            onChange()
        }
    }

    private var track: some View {
        ZStack(alignment: .top) {
            // Tick marks every 3 dB, with the center line picked out — the visual
            // reference that tells you how far from flat you have wandered.
            VStack(spacing: 0) {
                ForEach(0 ..< 9) { index in
                    Rectangle()
                        .fill(index == 4 ? Theme.hairline.opacity(3) : Theme.hairline)
                        .frame(height: index == 4 ? 1 : 0.5)
                    if index < 8 { Spacer(minLength: 0) }
                }
            }
            .frame(width: 22, height: trackHeight)

            Capsule()
                .fill(Theme.track)
                .frame(width: 3, height: trackHeight)

            // Fill from center toward the knob, so the sign of the gain is visible
            // before the number is read.
            Capsule()
                .fill(Theme.tint(forGain: gain).opacity(0.75))
                .frame(width: 3, height: abs(offset(for: gain)))
                .offset(y: gain > 0 ? offset(for: gain) + trackHeight / 2 : trackHeight / 2)

            knob
        }
        .frame(width: 34, height: trackHeight)
        .gesture(dragGesture)
    }

    private var knob: some View {
        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(white: 0.34), Color(white: 0.18)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .strokeBorder(Theme.tint(forGain: gain).opacity(gain == 0 ? 0.25 : 0.9), lineWidth: 1)
            )
            .overlay(
                Rectangle()
                    .fill(Theme.tint(forGain: gain).opacity(gain == 0 ? 0.35 : 1))
                    .frame(height: 1.5)
            )
            .frame(width: 22, height: knobHeight)
            .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
            .offset(y: knobOffset)
    }

    /// Vertical position of the knob center, measured from the top of the track.
    private var knobOffset: CGFloat {
        let usable = trackHeight - knobHeight
        let normalized = (gain - range.lowerBound) / (range.upperBound - range.lowerBound)
        return usable * (1 - normalized)
    }

    /// Distance from the center line for the fill capsule.
    private func offset(for gain: Double) -> CGFloat {
        let half = trackHeight / 2
        return -CGFloat(gain / range.upperBound) * half
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = dragStartGain ?? gain
                if dragStartGain == nil { dragStartGain = start }

                let span = range.upperBound - range.lowerBound
                let perPoint = span / Double(trackHeight - knobHeight)
                let proposed = start - Double(value.translation.height) * perPoint
                // Quarter-dB steps: fine enough to be musical, coarse enough to land on
                // a round number.
                gain = (proposed / 0.25).rounded() * 0.25
                gain = min(max(gain, range.lowerBound), range.upperBound)
                onChange()
            }
            .onEnded { _ in dragStartGain = nil }
    }

    private func label(for frequency: Double) -> String {
        frequency >= 1_000
            ? "\(Int((frequency / 1_000).rounded()))k"
            : "\(Int(frequency.rounded()))"
    }
}
