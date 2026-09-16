import Foundation

/// Shape of a single filter in the chain.
public enum BandType: String, Codable, Sendable, CaseIterable {
    /// Bell around `frequency`. The workhorse.
    case peaking
    /// Everything below `frequency` moves. What "bass" actually means.
    case lowShelf
    /// Everything above `frequency` moves.
    case highShelf
    /// Removes rumble below `frequency`; `gain` is ignored.
    case highPass
    /// Removes hiss above `frequency`; `gain` is ignored.
    case lowPass
}

/// One filter: where, how much, how wide.
public struct EQBand: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var type: BandType
    /// Center (peaking) or corner (shelf/pass) frequency in Hz.
    public var frequency: Double
    /// Gain in dB. Ignored by `highPass` and `lowPass`.
    public var gain: Double
    /// Bandwidth. Lower is wider. 0.707 is the neutral default.
    public var q: Double
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        type: BandType = .peaking,
        frequency: Double,
        gain: Double = 0,
        q: Double = 0.707,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.type = type
        self.frequency = frequency
        self.gain = gain
        self.q = q
        self.isEnabled = isEnabled
    }
}

/// How the output level is kept from clipping once bands are boosted.
public enum PreampMode: String, Codable, Sendable {
    /// Pull the level down by exactly the profile's worst-case boost. Never clips,
    /// costs volume.
    case automatic
    /// Use `manualPreamp` verbatim. The limiter is still the backstop.
    case manual
}

/// A complete EQ setting: the thing the UI edits and every engine renders.
public struct EQProfile: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var bands: [EQBand]
    public var preampMode: PreampMode
    /// dB, only consulted when `preampMode == .manual`.
    public var manualPreamp: Double

    public init(
        id: UUID = UUID(),
        name: String,
        bands: [EQBand],
        preampMode: PreampMode = .automatic,
        manualPreamp: Double = 0
    ) {
        self.id = id
        self.name = name
        self.bands = bands
        self.preampMode = preampMode
        self.manualPreamp = manualPreamp
    }

    public var activeBands: [EQBand] {
        bands.filter { $0.isEnabled }
    }

    /// The ten-band layout the UI ships with — ISO octave centers, the same spacing
    /// every hardware graphic EQ has used for forty years.
    public static let standardFrequencies: [Double] = [
        31.25, 62.5, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000,
    ]

    /// Bandwidth for the ten-band layout. Octave-spaced bands want roughly 1.4 — wide
    /// enough that neighbours join into a smooth curve, narrow enough that a fader
    /// still means what its label says.
    public static let standardQ = 1.41

    /// A flat ten-band profile, ready to be dragged.
    public static func flat(name: String = "Flat") -> EQProfile {
        tenBand(name: name, gains: Array(repeating: 0, count: standardFrequencies.count))
    }

    /// Builds a profile straight from ten fader positions.
    public static func tenBand(name: String, gains: [Double]) -> EQProfile {
        EQProfile(
            name: name,
            bands: zip(standardFrequencies, gains).map { frequency, gain in
                EQBand(frequency: frequency, gain: gain, q: standardQ)
            }
        )
    }
}
