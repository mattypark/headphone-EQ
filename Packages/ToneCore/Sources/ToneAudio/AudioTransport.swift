import Foundation
import ToneCore

/// How processed audio gets from us to the headphone.
///
/// Two implementations are planned: a Core Audio process tap (no install, the default)
/// and a virtual HAL driver (needs an admin install, kept as the fallback). The app only
/// ever talks to this protocol.
public protocol AudioTransport: AnyObject {
    var isRunning: Bool { get }
    /// Round-trip latency the transport adds, in milliseconds. Shown in the UI because
    /// it is the one honest cost of pipeline mode.
    var latencyMilliseconds: Double { get }

    func start() throws
    func stop()
    func setProfile(_ profile: EQProfile)
}

public enum TransportError: Error, LocalizedError {
    case noOutputDevice
    case tapCreationFailed(OSStatus)
    case aggregateCreationFailed(OSStatus)
    case ioProcFailed(OSStatus)
    case startFailed(OSStatus)
    case unsupportedFormat

    public var errorDescription: String? {
        switch self {
        case .noOutputDevice:
            "No audio output device is selected."
        case .tapCreationFailed(let status):
            "Could not create the system audio tap (\(status)). Grant audio recording permission in System Settings › Privacy & Security."
        case .aggregateCreationFailed(let status):
            "Could not create the aggregate audio device (\(status))."
        case .ioProcFailed(let status):
            "Could not install the audio callback (\(status))."
        case .startFailed(let status):
            "Could not start audio (\(status))."
        case .unsupportedFormat:
            "The output device uses an audio format this build does not handle."
        }
    }
}
