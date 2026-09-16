import Foundation

/// The suggested EQs — the carousel Sony's app has, built as ordinary profiles so a
/// preset is a starting point you keep dragging, never a mode you get locked into.
public enum Presets {
    public static let all: [EQProfile] = [
        flat, bassBoost, deepBass, vocal, podcast, lateNight, trebleBoost, loudness,
    ]

    public static let flat = EQProfile.flat()

    /// The one he asked for. A shelf rather than a 60 Hz bell, because "more bass"
    /// means the whole bottom end, not one note. The small 300 Hz dip keeps the boost
    /// from turning into mud — that dip is the difference between deep and boomy.
    public static let bassBoost = EQProfile(
        name: "Bass Boost",
        bands: [
            EQBand(type: .lowShelf, frequency: 80, gain: 6, q: 0.707),
            EQBand(type: .peaking, frequency: 300, gain: -1.5, q: 1.0),
            EQBand(type: .highShelf, frequency: 10_000, gain: 1, q: 0.707),
        ]
    )

    /// For headphones that genuinely reach low. Pushes sub-bass you feel more than hear,
    /// and clears more midrange to make room for it.
    public static let deepBass = EQProfile(
        name: "Deep Bass",
        bands: [
            EQBand(type: .lowShelf, frequency: 55, gain: 9, q: 0.707),
            EQBand(type: .peaking, frequency: 160, gain: -2, q: 0.9),
            EQBand(type: .peaking, frequency: 400, gain: -2.5, q: 1.1),
        ]
    )

    /// Pulls voices forward: rumble gone, boxiness gone, presence up.
    public static let vocal = EQProfile(
        name: "Vocal",
        bands: [
            EQBand(type: .highPass, frequency: 80, q: 0.707),
            EQBand(type: .peaking, frequency: 250, gain: -2.5, q: 1.0),
            EQBand(type: .peaking, frequency: 2_500, gain: 3, q: 0.9),
            EQBand(type: .highShelf, frequency: 8_000, gain: 1.5, q: 0.707),
        ]
    )

    /// Speech intelligibility over everything — spoken word, calls, lectures.
    public static let podcast = EQProfile(
        name: "Podcast",
        bands: [
            EQBand(type: .highPass, frequency: 90, q: 0.707),
            EQBand(type: .peaking, frequency: 200, gain: -3, q: 1.0),
            EQBand(type: .peaking, frequency: 3_000, gain: 4, q: 0.8),
            EQBand(type: .peaking, frequency: 6_500, gain: -2, q: 2.0),
        ]
    )

    /// Quiet listening. Equal-loudness curves say the ear loses bass and top end as
    /// volume drops, so give both back rather than turning everything up.
    public static let lateNight = EQProfile(
        name: "Late Night",
        bands: [
            EQBand(type: .lowShelf, frequency: 100, gain: 3.5, q: 0.707),
            EQBand(type: .peaking, frequency: 1_000, gain: -1, q: 0.8),
            EQBand(type: .highShelf, frequency: 7_000, gain: 2.5, q: 0.707),
        ]
    )

    public static let trebleBoost = EQProfile(
        name: "Treble Boost",
        bands: [
            EQBand(type: .highShelf, frequency: 6_000, gain: 5, q: 0.707),
            EQBand(type: .peaking, frequency: 9_000, gain: -2, q: 3.0),
        ]
    )

    /// Smile curve. Both ends up, middle untouched — the classic "makes everything
    /// sound bigger" setting.
    public static let loudness = EQProfile(
        name: "Loudness",
        bands: [
            EQBand(type: .lowShelf, frequency: 90, gain: 5, q: 0.707),
            EQBand(type: .peaking, frequency: 800, gain: -1.5, q: 0.8),
            EQBand(type: .highShelf, frequency: 8_000, gain: 4, q: 0.707),
        ]
    )
}
