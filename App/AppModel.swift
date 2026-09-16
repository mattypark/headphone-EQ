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
    private let deviceWatcher = DeviceWatcher()
    private var saveTask: Task<Void, Never>?

    init() {
        let device = CA.defaultOutputDevice.flatMap(CA.deviceName) ?? "Output"
        deviceName = device
        profile = ProfileStore().profile(forDevice: device)
        transport.setProfile(profile)

        deviceWatcher.onChange = { [weak self] name in
            self?.outputDeviceChanged(to: name)
        }
        deviceWatcher.start()

        // An equaliser you have to switch on every morning is an equaliser you stop
        // using. Come back the way it was left.
        if UserDefaults.standard.bool(forKey: Self.enabledKey) {
            enable()
        }
    }

    private static let enabledKey = "transport.enabled"

    /// The tap and aggregate device are bound to one output device, so a switch means
    /// tearing the pipeline down and building it again — and swapping in whatever curve
    /// belongs to the headphone that just arrived.
    private func outputDeviceChanged(to name: String) {
        let wasEnabled = isEnabled
        if wasEnabled {
            transport.stop()
            isEnabled = false
            latencyMilliseconds = 0
        }

        deviceName = name
        profile = store.profile(forDevice: name)
        transport.setProfile(profile)

        if wasEnabled { enable() }
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
            UserDefaults.standard.set(true, forKey: Self.enabledKey)
        } catch {
            errorMessage = error.localizedDescription
            isEnabled = false
        }
    }

    func disable() {
        transport.stop()
        isEnabled = false
        latencyMilliseconds = 0
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
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

    /// Load an AutoEQ ParametricEQ export — the measured correction curve published for
    /// a specific headphone. Bands beyond the engine's ceiling are dropped rather than
    /// silently ignored, and the user is told.
    func importAutoEQ(from url: URL) {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let name = url.deletingPathExtension().lastPathComponent
            var imported = try AutoEQImport.profile(from: text, name: name)

            if imported.bands.count > EQEngine.maxBands {
                let dropped = imported.bands.count - EQEngine.maxBands
                imported.bands = Array(imported.bands.prefix(EQEngine.maxBands))
                errorMessage = "Loaded \(name) — \(dropped) band\(dropped == 1 ? "" : "s") beyond the \(EQEngine.maxBands)-band limit were dropped."
            } else {
                errorMessage = nil
            }

            profile = imported
            profileChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
