import CoreAudio
import Foundation
import ToneAudio
import ToneCore

// Headless driver for the audio pipeline. Exists so the transport can be measured
// rather than described: `measure` runs the same signal through the machine twice —
// once flat, once with a preset — and prints the difference against what the profile
// promises. Anything that does not match is a bug in the pipeline, not an opinion.

setvbuf(stdout, nil, _IOLBF, 0)

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "help"

func preset(named name: String) -> EQProfile? {
    Presets.all.first { $0.name.lowercased().replacingOccurrences(of: " ", with: "") == name.lowercased().replacingOccurrences(of: " ", with: "") }
}

func option(_ flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

switch command {
case "devices":
    if let device = CA.defaultOutputDevice {
        print("default output: \(CA.deviceName(device) ?? "?")")
        print("  uid:         \(CA.deviceUID(device) ?? "?")")
        print("  sample rate: \(CA.nominalSampleRate(device)) Hz")
        print("  buffer:      \(CA.bufferFrameSize(device)) frames")
    } else {
        print("no default output device")
    }

case "presets":
    for profile in Presets.all {
        let peak = Headroom.peakGainDB(of: profile, sampleRate: 48_000)
        let preamp = Headroom.preampDB(for: profile, sampleRate: 48_000)
        let name = profile.name.padding(toLength: 14, withPad: " ", startingAt: 0)
        print(name + String(format: "peak %+5.1f dB   preamp %+5.1f dB   %d bands",
                            peak, preamp, profile.activeBands.count))
    }

case "run":
    let name = option("--preset") ?? "Bass Boost"
    guard let profile = preset(named: name) else {
        print("unknown preset '\(name)' — try: \(Presets.all.map(\.name).joined(separator: ", "))")
        exit(1)
    }
    let transport = ProcessTapTransport()
    transport.setProfile(profile)
    do {
        try transport.start()
    } catch {
        print("failed: \(error.localizedDescription)")
        exit(1)
    }
    print("running '\(profile.name)' on \(transport.outputDeviceName)")
    print(String(format: "added latency: %.1f ms", transport.latencyMilliseconds))
    print("ctrl-c to stop")
    signal(SIGINT) { _ in exit(0) }
    RunLoop.current.run()

case "measure":
    let name = option("--preset") ?? "Bass Boost"
    let seconds = Double(option("--seconds") ?? "5") ?? 5
    guard let profile = preset(named: name) else { print("unknown preset '\(name)'"); exit(1) }
    try Measurement.run(profile: profile, seconds: seconds)

default:
    print("""
    eqcli — headless driver for the headphone-EQ audio pipeline

      devices                              show the current output device
      presets                              list presets with their headroom
      run      [--preset NAME]             apply a preset to system audio
      measure  [--preset NAME] [--seconds N]
                                           play a test signal twice (flat, then the
                                           preset) and report the measured response
    """)
}
