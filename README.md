# G9 Keyboard Switch

**An easy way to manage your Samsung monitor and MX Keys keyboard together.**

Make your **Samsung Odyssey Neo G9** follow your **Logitech MX Keys S** keyboard as it
hops between your Mac and your Windows PC. Press the keyboard's Easy‑Switch key to move
to the other computer, and the monitor switches its input to match — automatically.

It lives quietly in your Mac's **menu bar**. No extra windows, no Dock icon, no fuss.

```
 ┌──────────────┐        press Easy-Switch          ┌──────────────┐
 │     Mac      │ ─────────────────────────────────▶│   Windows    │
 │  (HDMI 2)    │                                    │   (HDMI 1)   │
 └──────┬───────┘                                    └──────┬───────┘
        │  keyboard disconnects / reconnects (Bluetooth)    │
        └───────────────┐                    ┌──────────────┘
                        ▼                    ▼
                 ┌───────────────────────────────┐
                 │   G9 Keyboard Switch (menu bar)│
                 │   watches the keyboard,        │
                 │   tells the monitor to switch  │
                 └───────────────────────────────┘
```

## Why this exists

The MX Keys S already switches between computers with its Easy‑Switch keys — but your
monitor doesn't know that happened, so you still reach over and press the monitor's input
button every time. This app closes that gap: it watches the keyboard's Bluetooth
connection on the Mac and sends the monitor a DDC input‑switch command so the screen
follows the keyboard.

## How it works

- **Detection:** the Mac watches the selected keyboard's Bluetooth connection state
  (via `system_profiler`). When the keyboard leaves for Windows it disconnects; when it
  comes back it reconnects.
- **Switching:** the app sends the monitor a **DDC/CI** input command using the bundled
  [`m1ddc`](https://github.com/waydabber/m1ddc) helper (VCP feature `0x60`).
- **Manual is always there:** **Switch to Mac** / **Switch to Windows** in the menu work
  any time, independent of automation — the reliable fallback.

### Verified setup

This first release targets one confirmed configuration:

| Thing | Value |
|---|---|
| Monitor | Samsung Odyssey G95NC (57″ Neo G9), input feature VCP `0x60` |
| Windows | HDMI 1 → DDC value **5** |
| Mac | HDMI 2 → DDC value **6** (HDMI 3 has no DDC value on this firmware — see [What the hardware really does](#what-the-hardware-really-does)) |
| Keyboard | Logitech MX Keys S (`0x046D` / `0xB378`), Bluetooth |
| Mac | Apple Silicon (tested on M2 Max) |

Other monitors, inputs, and Macs may work but need their own calibration — they aren't
advertised as verified.

## Automation modes

Automation is **off by default** and starts **unarmed**. It only arms after your keyboard
makes a stable connection to the Mac while a mode is enabled — and arming never moves the
monitor. From there:

| Mode | Keyboard leaves the Mac | Keyboard returns to the Mac |
|---|---|---|
| **Manual** | nothing (you use the menu) | nothing |
| **Follow to Windows** | switch monitor to Windows (DDC value 5) | nothing |
| **Return to Mac** | nothing | switch monitor to Mac (DDC value 6) |
| **Follow both ways** | switch monitor to Windows | switch monitor to Mac |

> Both directions are plain DDC writes, and the monitor honours them even from the input
> that is not on screen (measured — see below). The [Windows companion](windows-companion/)
> does the Windows → Mac half too; running both is harmless, they send the same value.

> **An honest limitation:** a Bluetooth disconnect can't tell "switched to Windows" apart
> from "keyboard turned off / went to sleep / moved to a third device." Debouncing reduces
> false switches but can't eliminate them. That's why departure switching is an explicit,
> opt‑in mode.

## What the hardware really does

Measured on 2026‑09‑16 from the Windows PC (AMD GPU, HDMI 1) with the monitor's input
register (VCP `0x60`) read back after every write:

| Fact | Evidence |
|---|---|
| DDC writes work from either machine | brightness nudged and restored; input writes below |
| **5 = HDMI 1**, **6 = HDMI 2**, **15 (0x0F) = DisplayPort** | each write changed the register within ~5 s and the screen followed |
| **No value selects HDMI 3** | every single‑byte value 0x00–0xFF, plus the plausible two‑byte ones, left the register unchanged. The monitor *reports* `1` while on HDMI 3 but rejects `1` as a command. `7` (the earlier assumption) is rejected too. A diff of all 256 VCP codes between HDMI 1 and HDMI 3 showed no other input register. |
| Writes are honoured on an **inactive** input | writing 5 while the monitor showed HDMI 3 brought Windows back in ~1 s; the Mac app's write of 5 on keyboard departure works the same way |
| Moving the Mac to **HDMI 2** fixes it | companion writes 6 → monitor on HDMI 2 within 1–3 s, three times in a row; Mac app writes 5 → back on Windows before the keyboard has even reconnected |

Consequences:

- The earlier "only the on‑screen computer can switch the monitor" theory was wrong. The
  Mac's switch‑back never worked because `7` isn't a valid value, not because HDMI 3 was
  inactive. It looks like the DDC table was inherited from a two‑HDMI design and never
  extended to the third port.
- **The Mac lives on HDMI 2.** Mac → Windows is a write of `5`; Windows → Mac is a write
  of `6`. Either machine can send either value.
- The [Windows companion](windows-companion/) and the Mac app's return modes do the same
  job for Windows → Mac; run one or both.

## Install & run

Requirements: macOS 14+, Xcode / Swift 6 toolchain, an Apple Silicon Mac.

```sh
# Build the menu-bar app bundle (compiles + bundles m1ddc + ad-hoc signs it)
./Scripts/build-app.sh

# Launch it
open "dist/G9 Keyboard Switch.app"
```

A **display icon** appears at the top‑right of your menu bar. Click it to switch
manually or pick an automation mode.

> **⚠️ About "Switch to Windows":** it changes the monitor to HDMI 1, which blacks out
> *this* Mac's screen. To come back, press the monitor's **physical source button and
> choose HDMI 2**, or trigger **Switch to Mac** from the Windows machine's side. The app
> shows this recovery note whenever you request Windows.

To run the tests:

```sh
swift test
```

## What it does *not* do (by design, for now)

No keylogging (it only reads connection state, never keystrokes), no `sudo`/daemon, no
brightness/resolution/PBP control, no mouse switching, no network services, no Windows
installer. It runs as a normal user app.

## Project layout

```
Sources/G9Core/            Pure logic — no hardware. Fully unit-tested.
  Configuration.swift        settings model + validation
  SwitchPolicy.swift         the Mac-first arming state machine (the "brain")
  CommandCoordinator.swift   serialized monitor writes, retries, cancellation
  KeyboardStatusParser.swift structural Bluetooth-JSON parsing
  Diagnostics.swift          bounded, redactable event log
Sources/G9KeyboardSwitch/  The menu-bar app (SwiftUI) + hardware services
  DisplayController.swift     m1ddc wrapper (DDC input switching)
  KeyboardProvider.swift      system_profiler Bluetooth watcher
  MenuBarView.swift / G9App.swift / AppModel.swift
  Resources/m1ddc             bundled display-control helper (MIT)
Scripts/build-app.sh       builds the signed .app bundle
docs/superpowers/plans/    the full Release-1 implementation plan
```

## Status

- ✅ **Milestone 1 — Manual controller:** menu-bar app, monitor discovery, manual
  Mac/Windows switching, bundled helper. Built and running.
- ✅ Core engine for detection + automation modes (config, policy, coordinator,
  diagnostics, Bluetooth parser) — **36/36 tests passing**, including the required
  activation-gate and no-oscillation suites.
- ✅ **Windows companion** (C# tray app) built and running on the Windows PC; keyboard
  detection verified at ~1 s, DDC path verified (brightness, inputs 5/6/15).
- ✅ **Two‑way switching verified on hardware (2026‑09‑16):** Windows → Mac via the
  companion (value 6, ~3–5 s from Easy‑Switch), Mac → Windows via the Mac app (value 5).
- ⚠️ **Confirmed hardware limit:** the G95NC has **no DDC value for HDMI 3** (full
  0x00–0xFF sweep), so the Mac was moved to HDMI 2. See *What the hardware really does*.
- ⏳ **Unverified on the Mac:** the config default change (HDMI 2 = 6), the restored
  `Return to Mac` / `Follow both ways` menu items and the updated test were edited on the
  Windows PC. Run `swift test` and rebuild the app on the Mac.
- ⏳ Next: setup wizard, global shortcuts, launch-at-login, Developer‑ID signing +
  notarization (Mac).

See the implementation plan in `docs/superpowers/plans/` for the full milestone breakdown.

## Credits

Monitor control uses [`m1ddc`](https://github.com/waydabber/m1ddc) by waydabber (MIT
license — see `Sources/G9KeyboardSwitch/Resources/m1ddc-LICENSE`).
