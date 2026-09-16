import SwiftUI
import ToneCore

/// One vertical fader: tick-marked track, a knob you can throw, and a live dB readout.
///
/// Drag moves it; double-click returns it to zero. The whole point of a fader over a
/// number field is that the row of them *is* the frequency response, so the knob
/// positions have to be readable across the room.
struct BandFader: View {
    let frequency: Double
    @Binding var gain: Double
    let range: ClosedRange<Double>
    let onChange: () -> Void

    @State private var dragStartGain: Double?
    @State private var isDragging = false

    static let trackHeight: CGFloat = 158
    private let knobHeight: CGFloat = 16
    private let knobWidth: CGFloat = 26

    var body: some View {
        VStack(spacing: 7) {
            Text(gain == 0 ? "0" : String(format: "%+.1f", gain))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(gain == 0 ? Theme.textDim : Theme.tint(forGain: gain))
                .frame(height: 12)

            track

            Text(label(for: frequency))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textDim)
                .frame(height: 12)
        }
        .frame(width: 38)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            gain = 0
            onChange()
        }
    }

    private var track: some View {
        ZStack(alignment: .top) {
            // Recessed slot, so the knob reads as sitting *in* something.
            Capsule()
                .fill(Color.black.opacity(0.55))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
                .frame(width: 6, height: Self.trackHeight)

            // Fill from the centre line out to the knob: the direction of travel is
            // legible before the number is read.
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Theme.tint(forGain: gain), Theme.tint(forGain: gain).opacity(0.45)],
                        startPoint: gain > 0 ? .bottom : .top,
                        endPoint: gain > 0 ? .top : .bottom
                    )
                )
                .frame(width: 6, height: fillHeight)
                .offset(y: fillOffset)
                .opacity(gain == 0 ? 0 : 1)

            knob
        }
        .frame(width: 38, height: Self.trackHeight)
        .gesture(dragGesture)
    }

    private var knob: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.42), Color(white: 0.20)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            // Grip lines, the detail that makes a control look grabbable.
            VStack(spacing: 2.5) {
                ForEach(0 ..< 3) { _ in
                    Rectangle().fill(Color.black.opacity(0.35)).frame(height: 1)
                }
            }
            .padding(.horizontal, 6)

            Rectangle()
                .fill(Theme.tint(forGain: gain))
                .frame(height: 2)
                .opacity(gain == 0 ? 0.4 : 1)
        }
        .frame(width: knobWidth, height: knobHeight)
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(
                    Theme.tint(forGain: gain).opacity(gain == 0 ? 0.2 : 0.75),
                    lineWidth: isDragging ? 1.5 : 1
                )
        )
        .shadow(color: .black.opacity(0.6), radius: 3, y: 2)
        .shadow(
            color: Theme.tint(forGain: gain).opacity(gain == 0 ? 0 : 0.35),
            radius: isDragging ? 7 : 4
        )
        .offset(y: knobOffset)
        .animation(.interactiveSpring(duration: 0.12), value: isDragging)
    }

    /// Knob centre measured from the top of the track.
    private var knobOffset: CGFloat {
        let usable = Self.trackHeight - knobHeight
        let normalized = (gain - range.lowerBound) / (range.upperBound - range.lowerBound)
        return usable * (1 - normalized)
    }

    private var fillHeight: CGFloat {
        abs(CGFloat(gain / range.upperBound)) * (Self.trackHeight - knobHeight) / 2
    }

    private var fillOffset: CGFloat {
        gain > 0 ? Self.trackHeight / 2 - fillHeight : Self.trackHeight / 2
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = dragStartGain ?? gain
                if dragStartGain == nil {
                    dragStartGain = start
                    isDragging = true
                }

                let span = range.upperBound - range.lowerBound
                let perPoint = span / Double(Self.trackHeight - knobHeight)
                let proposed = start - Double(value.translation.height) * perPoint
                // Quarter-dB steps: fine enough to be musical, coarse enough to land on
                // a round number.
                gain = min(max((proposed / 0.25).rounded() * 0.25, range.lowerBound), range.upperBound)
                onChange()
            }
            .onEnded { _ in
                dragStartGain = nil
                isDragging = false
            }
    }

    private func label(for frequency: Double) -> String {
        frequency >= 1_000
            ? "\(Int((frequency / 1_000).rounded()))k"
            : "\(Int(frequency.rounded()))"
    }
}

/// The dB scale beside the faders. Without it the faders are just sticks.
struct FaderScale: View {
    let range: ClosedRange<Double>
    let steps: [Double]

    var body: some View {
        VStack(spacing: 7) {
            Spacer().frame(height: 12)
            ZStack(alignment: .top) {
                ForEach(steps, id: \.self) { value in
                    HStack(spacing: 3) {
                        Text(value == 0 ? "0" : String(format: "%+.0f", value))
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(value == 0 ? Theme.textDim : Theme.textDim.opacity(0.55))
                        Rectangle()
                            .fill(value == 0 ? Theme.hairline.opacity(3) : Theme.hairline)
                            .frame(width: 4, height: value == 0 ? 1 : 0.5)
                    }
                    .frame(width: 26, alignment: .trailing)
                    .offset(y: offset(for: value))
                }
            }
            .frame(width: 26, height: BandFader.trackHeight, alignment: .top)
            Spacer().frame(height: 12)
        }
    }

    private func offset(for value: Double) -> CGFloat {
        let normalized = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return BandFader.trackHeight * (1 - normalized) - 5
    }
}
