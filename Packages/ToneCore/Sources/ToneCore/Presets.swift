import Foundation

/// The suggested EQs, authored directly as positions on the ten faders.
///
/// They used to be three or four clever filters, which had two problems: applying one
/// replaced the ten-fader row with three faders, so the preset was invisible, and the
/// curves were too polite to hear. Now a preset is just where the faders go — you see
/// exactly what it did, and you can drag on from there.
public enum Presets {
    public static let all: [EQProfile] = [
        flat, bassBoost, deepBass, loudness, vocal, podcast, lateNight, trebleBoost,
    ]

    //                                      31   63  125  250  500   1k   2k   4k   8k  16k
    public static let flat = EQProfile.tenBand(
        name: "Flat",
        gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    )

    /// The one he asked for, and loud enough to actually hear. The upper bass tapers
    /// off instead of staying flat, which is what keeps a big low end from turning to
    /// mud at 250 Hz.
    public static let bassBoost = EQProfile.tenBand(
        name: "Bass Boost",
        gains: [10, 9, 6, 2, 0, 0, 0, 0, 1, 2]
    )

    /// Sub-bass you feel rather than hear, with the lower mids pulled back hard to
    /// make room for it.
    public static let deepBass = EQProfile.tenBand(
        name: "Deep Bass",
        gains: [14, 12, 7, 1, -3, -3, -1, 0, 1, 2]
    )

    /// Smile curve. Both ends up, middle scooped — the classic "everything sounds
    /// bigger" setting, and the most dramatic preset here.
    public static let loudness = EQProfile.tenBand(
        name: "Loudness",
        gains: [11, 9, 5, 0, -3, -3, -1, 3, 7, 9]
    )

    /// Pulls voices forward: rumble gone, boxiness gone, presence up.
    public static let vocal = EQProfile.tenBand(
        name: "Vocal",
        gains: [-6, -4, -1, 1, 3, 4, 5, 3, 1, 0]
    )

    /// Speech intelligibility over everything — spoken word, calls, lectures.
    public static let podcast = EQProfile.tenBand(
        name: "Podcast",
        gains: [-12, -7, -2, 1, 4, 5, 5, 2, -1, -4]
    )

    /// Quiet listening. The ear loses both ends as volume drops, so give both back
    /// rather than turning everything up and waking the house.
    public static let lateNight = EQProfile.tenBand(
        name: "Late Night",
        gains: [8, 7, 4, 0, -1, -2, 0, 2, 5, 6]
    )

    public static let trebleBoost = EQProfile.tenBand(
        name: "Treble Boost",
        gains: [0, 0, 0, 0, 0, 1, 4, 7, 8, 8]
    )
}
