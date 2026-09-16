# headphone-EQ

A system-wide equaliser for macOS, and a control app for headphones that have their own
DSP — the thing Sony ships for their headphones and nobody ships for everything else.

macOS has no built-in equaliser. So on a Mac, your AirPods sound exactly the way Apple
decided they should sound, in every app, forever. This fixes that.

## What it does

- **Pipeline EQ** — a 10-band parametric equaliser across all system audio. Works with
  any headphone: AirPods, Sony, wired, anything the Mac can output to.
- **Native EQ** — where a headphone exposes its own DSP over Bluetooth, drive that
  instead: zero latency, and the setting lives in the headphone.
- **Suggested EQs** — Bass Boost, Deep Bass, Vocal, Podcast, Late Night, Treble Boost,
  Loudness. A preset seeds the sliders; you keep dragging.
- **AutoEQ import** — load the measured correction curve published for your exact model.
- **Auto headroom** — boosting bass can't clip. The preamp ducks by exactly the profile's
  worst-case boost, with a soft limiter as backstop.

## Status

| Stage | |
|---|---|
| 0 · Transport spike | done — see [`docs/SPIKE.md`](docs/SPIKE.md) |
| 1 · Scaffold + repo | done |
| 2 · `ToneCore` DSP + tests | done — 18/18 passing |
| 3 · Core Audio tap transport | next |
| 4 · UI | |
| 5 · Presets + AutoEQ import | DSP side done, UI pending |
| 6 · Sony adapter | blocked on confirming the RFCOMM open |
| 7 · AirPods adapter | **cancelled** — macOS won't grant the channel |
| 8 · Polish | |

## What was learned the hard way

**AirPods cannot be EQ'd at the source on macOS.** Their control protocol is known — AACP
over L2CAP PSM `0x1001`, with opcode `0x0063` for custom EQ — but macOS never completes
an L2CAP channel open to a connected audio device, not even on the SDP PSM. `bluetoothd`
owns that link. AirPods therefore go through the pipeline engine like everything else.
Full evidence in [`docs/SPIKE.md`](docs/SPIKE.md).

**A third-party iPhone app cannot do this at all.** CoreBluetooth only speaks BLE GATT so
it can't reach the AirPods channel, and the sandbox has no cross-app audio tap. macOS
only, on purpose.

## Build

```sh
cd Packages/ToneCore && swift test    # 18 tests, no hardware needed
```

`ToneCore` is deliberately free of Core Audio and Bluetooth — it's pure DSP, so the part
that must be correct is the part that's easiest to test.
