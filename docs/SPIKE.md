# Stage 0 — transport spike

**Date:** 2026-09-16 · **Host:** macOS 26.6.2 (25G83), Xcode 26.6, Swift 6.3.3
**Question:** can a third-party macOS process open the control channel a headphone uses
for its own DSP, the way Sony's own app does?

Probe source: `spike/probe.swift` (read-only; nothing was written to either headphone
beyond the documented AAP handshake).

## AirPods Pro — L2CAP PSM 0x1001 (Apple Accessory Protocol)

**Result: blocked. Native EQ on AirPods is not available to us on macOS.**

| Attempt | Outcome |
|---|---|
| `openL2CAPChannelSync(PSM 0x1001)` | blocks forever, never returns |
| `openL2CAPChannelAsync(PSM 0x1001)`, 6 s / 15 s / 25 s waits | returns `kIOReturnSuccess`, `l2capChannelOpenComplete` **never fires** |
| Control test on SDP PSM `0x0001` | same — never completes |
| From a signed `.app` bundle with `NSBluetoothAlwaysUsageDescription` | same |
| With the Claude Code sandbox disabled | same |

The control test is the decisive one: even the SDP PSM, which any classic Bluetooth
device answers, never completes. So this is not PSM `0x1001` being singled out — macOS
does not hand out classic-L2CAP channels to an already-connected audio device at all.
`bluetoothd` owns that link and does not share it. Nothing was logged to `log show`
either; the request is simply never satisfied.

This is consistent with LibrePods existing only for Linux and Android, where the OS is
not already holding the AACP channel.

**Consequence:** Stage 7 (`AirPodsAdapter`) is cancelled. AirPods are served by the
pipeline engine, exactly like any other headphone. Worth revisiting only if Apple ever
publishes an accessory API — the opcodes (`0x0063` Custom EQ, `0x0053` Headphone
Accommodation) are known and the adapter would be small.

## Sony WH-1000XM4 — RFCOMM

**Result: promising. SDP is readable and the control channel is identified.**

`performSDPQuery` returned `kIOReturnSuccess` and the full service list, even with the
headphones powered off (macOS serves it from the pairing cache):

| Service | RFCOMM channel |
|---|---|
| Hands-Free unit | 1 |
| Headset | 2 |
| `Serial HPC` — **Sony headphone control, the one we want** | **9** |
| `IAPSERVER` | 10 |
| `Serial MC` | 11 |
| `GSOUND_BT_CONTROL` | 19 |
| `GSOUND_BT_AUDIO` | 20 |
| `Airoha_APP` | 21 |
| Amazon Alexa | 22 |

`Serial HPC` (HeadPhone Control) is Sony's own control pipe — the channel their app
drives the 5-band EQ and Clear Bass over. Note the first probe naively grabbed channel 1
(Hands-Free), which would have been the wrong pipe entirely; selection is now by service
name.

**Still to confirm:** the XM4 was powered off during the spike, so the RFCOMM open itself
is untested. Re-run `./probe sony 20` with the headphones on and connected.

## Verdict

- Pipeline engine is the base for everything, as planned. Unblocked.
- Sony native mode is worth building once the channel open is confirmed.
- AirPods native mode is dead on macOS. Documented here so nobody re-litigates it.
