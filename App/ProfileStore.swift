import Foundation
import ToneCore

/// Remembers a profile per headphone, so plugging in the Sonys doesn't hand you the
/// curve you built for the AirPods.
@MainActor
final class ProfileStore {
    private let defaults = UserDefaults.standard
    private let key = "profiles.byDevice"

    private var storage: [String: EQProfile] {
        get {
            guard let data = defaults.data(forKey: key),
                  let decoded = try? JSONDecoder().decode([String: EQProfile].self, from: data)
            else { return [:] }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: key)
        }
    }

    func profile(forDevice device: String) -> EQProfile {
        storage[device] ?? .flat()
    }

    func save(_ profile: EQProfile, forDevice device: String) {
        storage[device] = profile
    }
}
