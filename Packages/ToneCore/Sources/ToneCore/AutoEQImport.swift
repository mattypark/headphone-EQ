import Foundation

/// Reads AutoEQ ParametricEQ exports — the measured correction curves published for
/// thousands of real headphones.
///
/// Expected shape:
/// ```
/// Preamp: -6.8 dB
/// Filter 1: ON PK Fc 105 Hz Gain -2.2 dB Q 0.70
/// Filter 2: ON LSC Fc 105 Hz Gain 5.5 dB Q 0.70
/// ```
public enum AutoEQImport {
    public enum ImportError: Error, LocalizedError {
        case noFiltersFound

        public var errorDescription: String? {
            switch self {
            case .noFiltersFound:
                "No parametric filters found — is this an AutoEQ ParametricEQ export?"
            }
        }
    }

    public static func profile(from text: String, name: String) throws -> EQProfile {
        var bands: [EQBand] = []
        var preamp = 0.0
        var sawPreamp = false

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.lowercased().hasPrefix("preamp:") {
                let tokens = line.split(separator: " ")
                if tokens.count >= 2, let value = Double(tokens[1]) {
                    preamp = value
                    sawPreamp = true
                }
                continue
            }

            guard line.lowercased().hasPrefix("filter"), let band = parseFilter(line) else { continue }
            bands.append(band)
        }

        guard !bands.isEmpty else { throw ImportError.noFiltersFound }

        return EQProfile(
            name: name,
            bands: bands,
            // AutoEQ ships its own measured preamp; trust it over our own estimate.
            preampMode: sawPreamp ? .manual : .automatic,
            manualPreamp: preamp
        )
    }

    private static func parseFilter(_ line: String) -> EQBand? {
        let tokens = line.split(separator: " ").map(String.init)
        guard tokens.contains("ON") else { return nil }   // OFF filters are skipped

        func value(after keyword: String) -> Double? {
            guard let index = tokens.firstIndex(of: keyword), index + 1 < tokens.count else { return nil }
            return Double(tokens[index + 1])
        }

        guard let frequency = value(after: "Fc") else { return nil }

        let type: BandType
        switch tokens.first(where: { ["PK", "LSC", "HSC", "LS", "HS", "HPQ", "LPQ"].contains($0) }) {
        case "LSC", "LS": type = .lowShelf
        case "HSC", "HS": type = .highShelf
        case "HPQ": type = .highPass
        case "LPQ": type = .lowPass
        default: type = .peaking
        }

        return EQBand(
            type: type,
            frequency: frequency,
            gain: value(after: "Gain") ?? 0,
            q: value(after: "Q") ?? 0.707
        )
    }
}
