import Combine
import Foundation
import SwiftUI
import ToneAudio
import ToneCore

/// Everything the UI reads and writes. One profile, one transport, one device.
@MainActor
final class AppModel: ObservableObject {
    @Published var profile: EQProfile
    @Published private(set) var isEnabled = false
    @Published private(set) var deviceName = "—"
    @Published private(set) var latencyMilliseconds = 0.0
    @Published private(set) var errorMessage: String?

    private let transport = ProcessTapTransport()
    private let store = ProfileStore()
    private var saveTask: Task<Void, Never>?

    init() {
        let device = CA.defaultOutputDevice.flatMap(CA.deviceName) ?? "Output"
        deviceName = device
        profile = ProfileStore().profile(forDevice: device)
        transport.setProfile(profile)
    }

    /// Headroom the current profile costs, for the readout under the faders.
    var preampDB: Double {
        Headroom.preampDB(for: profile, sampleRate: 48_000)
    }

    func toggle() {
        isEnabled ? disable() : enable()
    }

    func enable() {
        do {
            try transport.start()
            transport.setProfile(profile)
            deviceName = transport.outputDeviceName
            latencyMilliseconds = transport.latencyMilliseconds
            isEnabled = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            isEnabled = false
        }
    }

    func disable() {
        transport.stop()
        isEnabled = false
        latencyMilliseconds = 0
    }

    /// Called continuously while a fader is dragged, so it must stay cheap: push to the
    /// engine immediately, write to disk only once the hand comes off.
    func profileChanged() {
        transport.setProfile(profile)
        saveTask?.cancel()
        saveTask = Task { [profile, deviceName] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            ProfileStore().save(profile, forDevice: deviceName)
        }
    }

    func apply(preset: EQProfile) {
        // Keep this profile's identity, take the preset's shape.
        profile = EQProfile(
            id: profile.id,
            name: preset.name,
            bands: preset.bands.map {
                EQBand(type: $0.type, frequency: $0.frequency, gain: $0.gain, q: $0.q, isEnabled: $0.isEnabled)
            },
            preampMode: preset.preampMode,
            manualPreamp: preset.manualPreamp
        )
        profileChanged()
    }

    func reset() {
        apply(preset: .flat())
    }
}
