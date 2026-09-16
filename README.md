# G9 Keyboard Switch

**An easy way to manage your Samsung monitor and MX Keys keyboard together.**

Make your **Samsung Odyssey Neo G9** follow your **Logitech MX Keys S** keyboard as it
hops between your Mac and your Windows PC. Press the keyboard's Easy‑Switch key to move
to the other computer, and the monitor switches its input to match — automatically.

It lives quietly in your Mac's **menu bar**. No extra windows, no Dock icon, no fuss.

```
 ┌──────────────┐        press Easy-Switch          ┌──────────────┐
 │     Mac      │ ─────────────────────────────────▶│   Windows    │
 │  (HDMI 3)    │                                    │   (HDMI 1)   │
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
| Mac | HDMI 3 → DDC value **7** |
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
| **Follow to Windows** | switch monitor to Windows | nothing — the **Windows companion** brings it back |

> The Mac app only automates the direction it physically can (Mac → Windows). The old
> "Return to Mac" / "Follow both ways" modes are gone from the menu because this monitor
> won't accept a switch‑back command from the Mac while Windows is displayed — see
> **Two machines, two halves** above. Install the [Windows companion](windows-companion/)
> for the return.

> **An honest limitation:** a Bluetooth disconnect can't tell "switched to Windows" apart
> from "keyboard turned off / went to sleep / moved to a third device." Debouncing reduces
> false switches but can't eliminate them. That's why departure switching is an explicit,
> opt‑in mode.

## Two machines, two halves (important)

Testing on real hardware revealed that the **G95NC only obeys input‑select DDC commands
that arrive over the input it is currently displaying.** While it shows Windows, the Mac
is on an inactive input, so the Mac's "switch back to me" command is accepted on the wire
(exit 0) but **silently ignored** by the monitor. In other words:

> Only the computer that is **currently on‑screen** can switch the monitor away from itself.

So full two‑way following needs **both** pieces, each doing the half it can:

| When the keyboard… | The monitor is showing… | So the switch is done by… |
|---|---|---|
| leaves the **Mac** → Windows | the Mac | the **Mac app** (this repo) ✅ |
| leaves **Windows** → Mac | Windows | the **[Windows companion](windows-companion/)** |

Run the Mac app **and** the Windows companion together for automatic switching in both
directions. With just the Mac app, "Switch to Windows" works automatically, but coming
back to the Mac must be done from the monitor's source button or the companion.

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
> choose HDMI 3**, or trigger **Switch to Mac** from the Windows machine's side. The app
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
- ✅ **Windows companion** (C# tray app) for the Windows → Mac half — see
  [`windows-companion/`](windows-companion/). Build/test on Windows.
- ⚠️ **Confirmed hardware limit:** the Mac cannot switch the monitor back to itself while
  Windows is displayed (the monitor ignores DDC on an inactive input). Use the Windows
  companion for automatic return. This is a monitor firmware behaviour, not an app bug.
- ⏳ Next: setup wizard, global shortcuts, launch-at-login, Developer‑ID signing +
  notarization (Mac); build/verify the companion on the Windows PC.

See the implementation plan in `docs/superpowers/plans/` for the full milestone breakdown.

## Credits

Monitor control uses [`m1ddc`](https://github.com/waydabber/m1ddc) by waydabber (MIT
license — see `Sources/G9KeyboardSwitch/Resources/m1ddc-LICENSE`).
