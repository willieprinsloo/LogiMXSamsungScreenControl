# G9 Keyboard Switch — Windows companion

A Windows **system tray** app that watches the MX Keys S keyboard and, when it
**leaves Windows** (you Easy‑Switch to the Mac), tells the G95NC to switch its input to
**HDMI 2 (the Mac)** with a DDC write of value `6`. Verified on hardware 2026‑09‑16:
about 3–5 s from Easy‑Switch to the monitor changing.

## Why the Mac is on HDMI 2

Hardware testing on 2026‑09‑16 showed the G95NC has **no DDC input value for HDMI 3**.
From this PC every single‑byte value 0x00–0xFF was written to VCP `0x60` and only
`5` (HDMI 1), `6` (HDMI 2) and `15` (DisplayPort) were honoured; the monitor reports `1`
while on HDMI 3 but rejects `1` as a command. Moving the Mac's cable to HDMI 2 made the
switch work immediately. See the root README, *What the hardware really does*.

The monitor also honours writes from the input that is **not** on screen, so the Mac
app's own `Return to Mac` mode can do this half as well. Running both is fine — they
send the same value.

## Requirements

- Windows 10 (build 19041 / 2004) or Windows 11
- [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0) (to build) — end users can
  instead run a published build (see below)
- The monitor connected to the Windows PC with **DDC/CI enabled** in the monitor's OSD menu
- The MX Keys S paired to Windows over Bluetooth

## Build & run

From this `windows-companion` folder in a Windows terminal:

```powershell
dotnet run -c Release
```

Or build a self‑contained exe you can drop anywhere:

```powershell
dotnet publish -c Release -r win-x64 --self-contained false -o publish
.\publish\G9WindowsCompanion.exe
```

A tray icon appears. Right‑click it for status, **Switch monitor to Mac now** (manual
fallback), **Pause**, **Open log folder**, and **Quit**.

## One-shot installer (recommended)

Open PowerShell in this folder and run:

```powershell
.\install.ps1
```

This publishes the project (if needed), copies it to
`%LOCALAPPDATA%\Programs\G9WindowsCompanion\`, creates a Startup‑folder shortcut
so it comes up on every login, and launches it. No admin rights required.

To remove:

```powershell
.\uninstall.ps1          # keeps logs
.\uninstall.ps1 -PurgeLogs
```

## Manual start-at-login (if you prefer)

Press `Win+R`, type `shell:startup`, and drop a shortcut to `G9WindowsCompanion.exe`
in that folder. (Or create a Task Scheduler task "At log on".)

## First run — check the log

Open the tray menu → **Open log folder** (or look in
`%LOCALAPPDATA%\G9WindowsCompanion\companion.log`). On startup it logs:

- every **physical monitor** it found, with an index and description
- each keyboard **observation** (`Connected` / `Disconnected` / `Unknown`) and arming
- every DDC write and its result

Use it exactly like the Mac's logs — send it to me if something misbehaves.

## Configuration (optional)

Defaults match the verified setup, so it should work out of the box. To override, create
`settings.json` next to the exe (or in `%LOCALAPPDATA%\G9WindowsCompanion\`):

```json
{
  "KeyboardNameContains": "MX KEYS",
  "KeyboardAddress": null,
  "VcpInputFeature": 96,
  "MacInputValue": 6,
  "MonitorIndex": -1,
  "PollIntervalSeconds": 1.0,
  "DepartureDebounceSeconds": 3.0,
  "ArrivalDebounceSeconds": 1.0
}
```

- **MonitorIndex** `-1` writes to every monitor that accepts it (fine for one external
  display). If you have several monitors and the wrong one switches, set the index shown
  for the G95NC in the log.
- **KeyboardAddress** — if two "MX KEYS" devices are paired, set the exact Bluetooth
  address (from the log) to disambiguate; otherwise leave `null` to match by name.
- **MacInputValue** `6` = HDMI 2, where the Mac is plugged in (VCP `96` = `0x60`).
  Known‑good values on this monitor: `5` HDMI 1, `6` HDMI 2, `15` DisplayPort. HDMI 3
  has no value (see above). The monitor takes ~1–5 s to act on a write.

## How to test

1. Start the companion on Windows (monitor showing Windows).
2. Make sure it's **armed** (tray status: "Armed (keyboard on Windows)" — keyboard
   connected to Windows for a couple of seconds).
3. Easy‑Switch the keyboard **to the Mac**. Within ~3–5s the monitor should switch to
   HDMI 2 and show the Mac; the log shows the departure and
   `SetVCPFeature(... value=6) -> ok`.
4. `ok` only means the driver accepted the I²C write, not that the monitor obeyed. If
   the screen doesn't change, check the Mac really is on HDMI 2 and that DDC/CI is on.

## Notes / limitations

- If DDC/CI is disabled in the monitor OSD, `SetVCPFeature` fails — enable it.
- Bluetooth connection status is read from the paired device's `ConnectionStatus`
  (via `BluetoothLEDevice` / `BluetoothDevice`), which costs milliseconds per poll. A
  query failure, or the keyboard being unpaired, surfaces as `Unknown` and never
  triggers a switch (same conservative rule as the Mac app). On startup the log shows a
  `keyboard resolved` line with the name and address it locked on to.
- A keyboard power‑off looks like a departure — same inherent ambiguity documented for the
  Mac app. Use **Pause** or the manual menu item if that becomes a nuisance.
