import CoreAudio
import Foundation

/// Thin helpers over the Core Audio property API, which is otherwise four lines of
/// boilerplate per read.
public enum CA {
    static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func value<T>(
        _ objectID: AudioObjectID,
        _ address: AudioObjectPropertyAddress,
        default fallback: T
    ) -> T {
        var address = address
        var size = UInt32(MemoryLayout<T>.size)
        var value = fallback
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, $0)
        }
        return status == noErr ? value : fallback
    }

    static func string(
        _ objectID: AudioObjectID,
        _ address: AudioObjectPropertyAddress
    ) -> String? {
        var address = address
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?
        let status = withUnsafeMutablePointer(to: &value) {
            $0.withMemoryRebound(to: UInt8.self, capacity: Int(size)) {
                AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, $0)
            }
        }
        guard status == noErr else { return nil }
        return value as String?
    }

    /// The device macOS is currently sending sound to.
    public static var defaultOutputDevice: AudioObjectID? {
        let id = value(
            AudioObjectID(kAudioObjectSystemObject),
            address(kAudioHardwarePropertyDefaultOutputDevice),
            default: AudioObjectID(kAudioObjectUnknown)
        )
        return id == kAudioObjectUnknown ? nil : id
    }

    public static func deviceUID(_ deviceID: AudioObjectID) -> String? {
        string(deviceID, address(kAudioDevicePropertyDeviceUID))
    }

    public static func deviceName(_ deviceID: AudioObjectID) -> String? {
        string(deviceID, address(kAudioObjectPropertyName))
    }

    public static func nominalSampleRate(_ deviceID: AudioObjectID) -> Double {
        value(deviceID, address(kAudioDevicePropertyNominalSampleRate), default: 48_000)
    }

    /// Buffer size in frames — one half of the latency figure shown in the UI.
    public static func bufferFrameSize(_ deviceID: AudioObjectID) -> UInt32 {
        value(deviceID, address(kAudioDevicePropertyBufferFrameSize), default: 512)
    }

    /// Audio object representing this process, needed to exclude ourselves from a
    /// global tap — otherwise the tap hears our own output and the room folds in on
    /// itself.
    static func processObjectID(pid: pid_t) -> AudioObjectID? {
        var address = self.address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var pid = pid
        var objectID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            &pid,
            &size,
            &objectID
        )
        return status == noErr && objectID != kAudioObjectUnknown ? objectID : nil
    }

    /// Stream format of a tap object.
    static func tapFormat(_ tapID: AudioObjectID) -> AudioStreamBasicDescription? {
        var address = self.address(kAudioTapPropertyFormat)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format)
        return status == noErr ? format : nil
    }
}
