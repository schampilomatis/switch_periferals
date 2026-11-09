# switch_peripherals

Scripts to switch monitors between a MacBook (M1 Max) and a Windows PC.

## Hardware

### Host — MacBook Pro (M1 Max)
- Apple Silicon (arm64), macOS
- Built-in Liquid Retina XDR display (3024x1964, always on Mac)

### External monitors (dual-input, both computers plugged in simultaneously)
| Model | Native res | Notes |
|-------|-----------|-------|
| HP E243 | 1920x1080 @ 60Hz | Business monitor, DP + HDMI + VGA inputs, DDC/CI supported |
| MSI MPG341CX OLED | 3440x1440 @ 240Hz | UWQHD OLED, DP 1.4 + HDMI 2.1 + USB-C, DDC/CI supported |

Each monitor receives one cable from Mac and one from PC. Switching is done by changing the monitor's active input via DDC/CI over the still-connected cable.

### Peripherals (deferred, see below)
| Device | Model | Transport |
|--------|-------|-----------|
| Mouse | Logitech MX Master 2S | Bluetooth (`EF:3D:E5:F3:85:9F`, VID `0x046D` / PID `0xB019`) |
| Keyboard | Royal Kludge RK-S98RGB | Bluetooth (`FF:23:00:0D:AF:08`) |

Both peripherals are Bluetooth-paired to both computers on separate BT channels.

## Scope

### In scope now: monitor input switching (macOS side)
Switch both external monitors between the Mac input and the PC input from a single command run on the Mac. Built-in laptop display remains on Mac (unaffected).

Approach: BetterDisplay CLI (`betterdisplaycli`, free DDC features only) for the DDC input switch, and `displayplacer` (free) to mirror the externals into the built-in display while the PC owns them — the free replacement for BetterDisplay Pro's `--connected=on|off` connect/disconnect. **No paid features are used.**

- App: BetterDisplay 4.3.6 (free; must be running — script auto-launches it with `open -g -a BetterDisplay`).
- CLI path (hard-coded in script): `/Users/schampilomat/.local/bin/betterdisplaycli`.
- Install: `brew install waydabber/betterdisplay/betterdisplaycli` plus the BetterDisplay app, and `brew install displayplacer`.
- List displays (BetterDisplay): `betterdisplaycli get --identifiers`.
- Set input (free DDC write): `betterdisplaycli set --name="<NAME>" --vcp=inputSelect --ddc=<value>`.
- Read input (free DDC read): `betterdisplaycli get --name="<NAME>" --feature=ddc --vcp=inputSelect`. Used as the toggle-state probe.
- List displays (displayplacer): `displayplacer list` — produces the full restore command at the end; `./switch.sh snapshot` prints just that line.
- **Pro-only (not used):** `--feature=connected` get/set and `--connected=on|off`. These require a paid BetterDisplay Pro license and silently return `Failed.` without one. Do not add them back — the mirror/extend toggle via displayplacer replaces them.

### Free "disconnect" via mirroring
When switching to PC, the script mirrors both externals into the built-in display (via `displayplacer` with `id:A+B+C ...`). Effect: windows migrate back to the built-in, cursor can't wander off into dead area, no "ghost" extended desktop. The GPU still drives the ports (small cost — negligible), but the externals are showing PC input anyway so the invisible Mac mirror is harmless. When switching back to Mac, the script restores the extended arrangement first (so the Mac is driving the ports and DDC/CI is reachable), then flips DDC inputs.

### Why not m1ddc / ddcctl / displayplacer `enabled:false`
- **m1ddc** (free, standalone CLI): works for the MSI (USB-C/DP Alt Mode) but **cannot address the HP E243** — the HP is on the Mac's built-in HDMI port, which m1ddc explicitly does not support. Also, in practice its `get` reads returned stuck/placeholder values here, so even reads weren't trustworthy.
- **ddcctl**: fails with "Failed to acquire framebuffer device for display" on this M1 Max under current macOS.
- **`displayplacer enabled:false`**: silently no-ops on recent macOS for externals the user hasn't explicitly disabled via a private API — not a reliable disconnect.
- A tiny Swift helper calling `CGSConfigureDisplayEnabled` would work but uses private APIs that break across macOS versions. Mirroring is the robust path.

### Confirmed port map (decimal VCP input source values)
| Monitor | Mac side | PC side |
|---------|---------|---------|
| HP E243 | HDMI = **17** | DisplayPort = **15** |
| MSI MPG341CX OLED | Mac cable = **16** | DisplayPort = **15** |

Values match the constants in `switch.sh` (`HP_MAC`, `HP_PC`, `MSI_MAC`, `MSI_PC`). MSI Mac-side value was previously recorded as 27 (USB-C) — current cabling reports 16, revisit if the Mac cable changes.

### Script
`switch.sh` at the repo root.

- `./switch.sh` — toggle. Probes the MSI's current input via free DDC read (`--feature=ddc --vcp=inputSelect`): if the value equals `MSI_MAC` (16) we're on Mac → switch to PC; otherwise → switch to Mac.
- `./switch.sh pc` — set both monitors to the PC input.
- `./switch.sh mac` — set both monitors to the Mac input.

The script auto-launches BetterDisplay.app if it isn't running, then waits up to ~10s for the CLI to become responsive.

Displays are matched by BetterDisplay display name (`HP E243`, `MPG341CX OLED`) since numeric IDs can shift on replug.

### Deferred
- **Mouse switching** — currently the physical channel button on the mouse bottom. Option: Logi Options+ (Flow — software cursor crossover over LAN). Not decided.
- **Keyboard switching** — RK-S98RGB has no host-side API; BT channel change is physical Fn+Q/W/E only. Software alternatives considered:
  - Deskflow / Barrier / Synergy — share keyboard+mouse over LAN (~1–5 ms wired latency). Requires both PCs running client/server. Not decided.
  - Hardware USB HID KVM switch — pure USB-only, video stays direct so no graphics compromise. Not decided.
- **Coordinated active-screen switch** — if Deskflow is chosen, the script should also fire a Deskflow hotkey via `osascript` after switching monitors so cursor/keyboard input follows the visible screen.
- **Windows-side equivalent script** — after macOS side works.

## Repository layout
```
/switch.sh   # main entry, toggles both monitors (macOS)
/CLAUDE.md   # this file
/windows/    # planned, not yet created
```

## Notes / gotchas
- BetterDisplay app must be running; if it's not, every CLI call returns `Failed. Request timed out. BetterDisplay might not be running…`. The script auto-launches it.
- Do **not** reintroduce `--feature=connected` or `--connected=on|off` — those are BetterDisplay Pro features and silently return `Failed.` without a license. Any DDC VCP read/write (including `--vcp=inputSelect`) is free and sufficient.
- Display names in BetterDisplay can differ from EDID product names; the script matches on `--name=` (BetterDisplay display name). Check with `betterdisplaycli get --identifiers`.
- MSI OLED sometimes takes a few seconds after input change; script should not assume synchronous.
- Empirically (2026-10-05) the Mac can still DDC-read a monitor while it's showing the PC input — observed `inputSelect=15` on both displays while they were pointed at the PC. So PC→Mac switches may work from the Mac side too, as long as the Mac GPU hasn't put the port to sleep. The Windows-side script is still the reliable fallback when the Mac port is asleep.
