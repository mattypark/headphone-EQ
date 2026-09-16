import SwiftUI

/// The look: a piece of studio hardware, not a settings pane.
///
/// Dark graphite panel, one warm accent for boost and one cool one for cut. Color
/// carries meaning here — a fader's tint tells you which direction it is pushing
/// before you read the number.
enum Theme {
    static let panel = Color(red: 0.055, green: 0.059, blue: 0.071)
    static let panelRaised = Color(red: 0.086, green: 0.090, blue: 0.106)
    static let hairline = Color.white.opacity(0.07)
    static let track = Color.white.opacity(0.10)

    static let text = Color(red: 0.92, green: 0.92, blue: 0.93)
    static let textDim = Color(red: 0.55, green: 0.56, blue: 0.60)

    /// Boost: warm amber. Cut: cool cyan. Neutral: bone.
    static let boost = Color(red: 1.0, green: 0.68, blue: 0.29)
    static let cut = Color(red: 0.40, green: 0.78, blue: 0.95)
    static let neutral = Color(red: 0.72, green: 0.73, blue: 0.76)

    static func tint(forGain gain: Double) -> Color {
        if gain > 0.25 { return boost }
        if gain < -0.25 { return cut }
        return neutral
    }

    static let numerals = Font.system(size: 10, weight: .medium, design: .monospaced)
    static let label = Font.system(size: 10, weight: .medium, design: .rounded)
    static let title = Font.system(size: 13, weight: .semibold, design: .rounded)
}
