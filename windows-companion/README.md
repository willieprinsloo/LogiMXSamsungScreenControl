# G9 Keyboard Switch — Windows companion

The other half of the two‑way switch. Runs in the Windows **system tray** and, when
your MX Keys S keyboard **leaves Windows** (you Easy‑Switch to the Mac), tells the
G95NC to switch its input to **HDMI 3 (the Mac)**.

## Why this exists

The Samsung G95NC only obeys input‑select DDC commands that arrive over the input it's
**currently displaying**. So:

- **Mac → Windows** is handled by the **Mac app** (the Mac is on‑screen when its keyboard
  leaves, so it can switch the monitor away to Windows).
- **Windows → Mac** must be handled **here** (Windows is on‑screen when its keyboard
  leaves, so only Windows can switch the monitor away to the Mac).

Each machine only ever switches the monitor *away from itself*. Run **both** the Mac app
and this companion for full two‑way following.

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

## Start automatically at login

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
  "MacInputValue": 7,
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
- **MacInputValue** `7` = HDMI 3 on this monitor (VCP `96` = `0x60`).

## How to test

1. Start the companion on Windows (monitor showing Windows).
2. Make sure it's **armed** (tray status: "Armed (keyboard on Windows)" — keyboard
   connected to Windows for a couple of seconds).
3. Easy‑Switch the keyboard **to the Mac**. Within ~3–4s the monitor should switch to
   HDMI 3 and show the Mac.
4. If it doesn't, open the log — it shows whether the departure was detected and whether
   `SetVCPFeature` succeeded (and on which monitor).

## Notes / limitations

- If DDC/CI is disabled in the monitor OSD, `SetVCPFeature` fails — enable it.
- Bluetooth connection status is polled via the Windows association‑endpoint
  `IsConnected` property; a query failure surfaces as `Unknown` and never triggers a
  switch (same conservative rule as the Mac app).
- A keyboard power‑off looks like a departure — same inherent ambiguity documented for the
  Mac app. Use **Pause** or the manual menu item if that becomes a nuisance.
