import CoreAudio
import Foundation

/// Notices when macOS starts sending sound somewhere else.
///
/// The tap and the aggregate device are both bound to one output device, so switching
/// from AirPods to speakers leaves the pipeline pointed at hardware nobody is listening
/// to. Watching the default-output property lets the transport rebuild itself, and lets
/// the UI load that headphone's own profile.
public final class DeviceWatcher: @unchecked Sendable {
    /// Called on the main queue with the new device's name.
    public var onChange: ((String) -> Void)?

    private var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private var block: AudioObjectPropertyListenerBlock?
    private var lastDeviceID = AudioObjectID(kAudioObjectUnknown)

    public init() {}

    deinit { stop() }

    public func start() {
        guard block == nil else { return }
        lastDeviceID = CA.defaultOutputDevice ?? AudioObjectID(kAudioObjectUnknown)

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            guard let device = CA.defaultOutputDevice, device != lastDeviceID else { return }
            lastDeviceID = device
            let name = CA.deviceName(device) ?? "Output"
            DispatchQueue.main.async { self.onChange?(name) }
        }
        block = listener

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listener
        )
    }

    public func stop() {
        guard let block else { return }
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block
        )
        self.block = nil
    }
}
