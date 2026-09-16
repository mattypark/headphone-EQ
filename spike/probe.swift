// Stage 0 spike — read-only Bluetooth transport probe.
// Answers one question: can a macOS userspace process open the control channel
// each headphone uses for its own DSP, while macOS is already talking to it?
//
// Probe A: AirPods  — L2CAP PSM 0x1001 (Apple Accessory Protocol).
// Probe B: Sony XM4 — SDP service dump, then RFCOMM to the Sony SPP channel.
//
// Nothing is written to either headphone beyond the documented AAP handshake.
// Throwaway code: deleted once docs/SPIKE.md records the findings.

import Foundation
import IOBluetooth

setvbuf(stdout, nil, _IOLBF, 0)

// Bluetooth addresses are personal hardware identifiers, so they are supplied by the
// operator rather than committed:
//   AIRPODS_ADDR=xx-xx-xx-xx-xx-xx SONY_ADDR=xx-xx-xx-xx-xx-xx ./probe both 20
// Find them with: system_profiler SPBluetoothDataType
let environment = ProcessInfo.processInfo.environment
let airpodsAddress = environment["AIRPODS_ADDR"] ?? ""
let sonyAddress    = environment["SONY_ADDR"] ?? ""
let aapPSM = BluetoothL2CAPPSM(ProcessInfo.processInfo.environment["PSM"].flatMap { UInt16($0, radix: 16) } ?? 0x1001)

func hex(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined(separator: " ")
}

func log(_ message: String) {
    print("[\(String(format: "%.3f", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1000)))] \(message)")
}

// MARK: - Probe A: AirPods over L2CAP

final class L2CAPProbe: NSObject, IOBluetoothL2CAPChannelDelegate {
    private var channel: IOBluetoothL2CAPChannel?

    // Documented AAP handshake, as decoded by the LibrePods project.
    private let handshake = Data([
        0x00, 0x00, 0x04, 0x00, 0x01, 0x00, 0x02, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    ])

    func run() {
        guard let device = IOBluetoothDevice(addressString: airpodsAddress) else {
            log("PROBE A: could not resolve device \(airpodsAddress)"); return
        }
        log("PROBE A: device=\(device.name ?? "?") connected=\(device.isConnected())")

        var opened: IOBluetoothL2CAPChannel?
        let status = device.openL2CAPChannelAsync(&opened, withPSM: aapPSM, delegate: self)
        guard status == kIOReturnSuccess else {
            log("PROBE A: RESULT=FAIL openL2CAPChannelAsync(PSM 0x1001) -> \(String(format: "0x%08x", status))")
            log("PROBE A: meaning macOS refused outright — most likely bluetoothd already owns AACP")
            return
        }
        channel = opened
        log("PROBE A: open requested, waiting for l2capChannelOpenComplete…")
    }

    func l2capChannelOpenComplete(_ l2capChannel: IOBluetoothL2CAPChannel!, status error: IOReturn) {
        guard error == kIOReturnSuccess else {
            log("PROBE A: RESULT=FAIL openComplete -> \(String(format: "0x%08x", error))")
            return
        }
        log("PROBE A: RESULT=CHANNEL OPEN on PSM 0x1001")
        var bytes = [UInt8](handshake)
        let write = l2capChannel.writeAsync(&bytes, length: UInt16(bytes.count), refcon: nil)
        log("PROBE A: handshake write -> \(String(format: "0x%08x", write)) bytes=\(hex(handshake))")
    }

    func l2capChannelData(_ l2capChannel: IOBluetoothL2CAPChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        let data = Data(bytes: dataPointer, count: dataLength)
        log("PROBE A: <- \(dataLength) bytes: \(hex(data))")
    }

    func l2capChannelClosed(_ l2capChannel: IOBluetoothL2CAPChannel!) {
        log("PROBE A: channel closed by remote")
    }

    func close() { channel?.close() }
}

// MARK: - Probe B: Sony XM4 over RFCOMM

final class RFCOMMProbe: NSObject, IOBluetoothRFCOMMChannelDelegate {
    private var channel: IOBluetoothRFCOMMChannel?

    func run() {
        guard let device = IOBluetoothDevice(addressString: sonyAddress) else {
            log("PROBE B: could not resolve device \(sonyAddress)"); return
        }
        log("PROBE B: device=\(device.name ?? "?") connected=\(device.isConnected())")

        let sdp = device.performSDPQuery(nil)
        log("PROBE B: performSDPQuery -> \(String(format: "0x%08x", sdp))")

        guard let services = device.services as? [IOBluetoothSDPServiceRecord], !services.isEmpty else {
            log("PROBE B: RESULT=NO SERVICES — headphone is probably powered off or unpaired from this Mac")
            return
        }

        // Sony exposes its control protocol on the "Serial HPC" (HeadPhone Control)
        // SPP record. Channel 1 is Hands-Free and would be the wrong pipe entirely.
        var sppChannelID: BluetoothRFCOMMChannelID = 0
        for service in services {
            var channelID: BluetoothRFCOMMChannelID = 0
            let hasRFCOMM = service.getRFCOMMChannelID(&channelID) == kIOReturnSuccess
            let name = service.getServiceName() ?? "(unnamed)"
            log("PROBE B: service '\(name)' rfcomm=\(hasRFCOMM ? String(channelID) : "-")")
            if hasRFCOMM, name == "Serial HPC" { sppChannelID = channelID }
        }

        guard sppChannelID != 0 else {
            log("PROBE B: RESULT=FAIL no RFCOMM service advertised"); return
        }

        var opened: IOBluetoothRFCOMMChannel?
        let status = device.openRFCOMMChannelAsync(&opened, withChannelID: sppChannelID, delegate: self)
        guard status == kIOReturnSuccess else {
            log("PROBE B: RESULT=FAIL openRFCOMMChannelAsync(\(sppChannelID)) -> \(String(format: "0x%08x", status))")
            return
        }
        channel = opened
        log("PROBE B: open requested on RFCOMM \(sppChannelID), waiting…")
    }

    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        guard error == kIOReturnSuccess else {
            log("PROBE B: RESULT=FAIL openComplete -> \(String(format: "0x%08x", error))")
            return
        }
        log("PROBE B: RESULT=CHANNEL OPEN on RFCOMM — listening, writing nothing")
    }

    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        let data = Data(bytes: dataPointer, count: dataLength)
        log("PROBE B: <- \(dataLength) bytes: \(hex(data))")
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        log("PROBE B: channel closed by remote")
    }

    func close() { channel?.close() }
}

// MARK: - Entry

let mode = CommandLine.arguments.dropFirst().first ?? "both"
log("host: macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")

var a: L2CAPProbe?
var b: RFCOMMProbe?

if mode == "airpods" || mode == "both" {
    if airpodsAddress.isEmpty { log("set AIRPODS_ADDR to probe the AirPods") }
    else { a = L2CAPProbe(); a?.run() }
}
if mode == "sony" || mode == "both" {
    if sonyAddress.isEmpty { log("set SONY_ADDR to probe the Sony headphones") }
    else { b = RFCOMMProbe(); b?.run() }
}

let waitSeconds = Double(CommandLine.arguments.dropFirst().dropFirst().first ?? "") ?? 6
RunLoop.current.run(until: Date().addingTimeInterval(waitSeconds))
a?.close()
b?.close()
log("probe finished")
