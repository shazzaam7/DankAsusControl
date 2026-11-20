# ASUS Control Center for DMS

ASUS laptop controls integrated into [Dux Modular Shell (DMS)](https://github.com/AvengeMedia/DankMaterialShell). Manage power profiles, GPU modes, battery charging, display options, and performance tuning without leaving your desktop.

## Requirements

- **DMS 2.2 or newer** recommended (the manifest's minimum is `requires_dms: >=2.0.0`).
- **asusctl 6.x** with the `asusd` daemon running. The plugin checks for `asusctl` at startup and will not enable if it is missing.
- An ASUS laptop with hardware supported by asusctl.

Some features (GPU modes, charge limits, tuning, keyboard backlight) depend on the attributes your device exposes through asusctl; unsupported sections are hidden automatically.

## Features

- **Power profiles** — switch between Quiet, Balanced, Performance, and any other profiles your device reports.
- **GPU modes** — choose Integrated, Hybrid, or Ultimate (on supported machines). Changing modes queues the change in asusd and **requires a reboot** to apply.
- **Battery charge limit and one-shot charging** — set a persistent charge limit (20–100%, step 5) or run a one-shot charge to 100%.
- **Panel overdrive** — toggle on supported displays.
- **Screen auto brightness** — toggle ambient-light-based brightness adjustment.
- **NVIDIA power tuning** — adjust TGP, dynamic boost, and temperature target where supported.
- **CPU power limits** — adjust PL1/PL2/PL3 limits on supported hardware under "CPU Power Limits (advanced)".
- **Keyboard backlight** — set the backlight to Off, Low, Med, or High.
- **Control Center tile** — a compact tile that shows the active profile and battery percentage; clicking it cycles profiles, and a detail panel offers one button per profile.
- **Battery stats** — percentage, state, health, capacity/energy, charge rate, and time remaining from DMS's battery service.

> Changing GPU mode and some hardware options is handled entirely by asusctl/asusd. DMS may reapply its own configured power profile when the power source changes (AC ↔ battery); the popout refreshes from asusctl so the displayed profile always reflects reality.

## Installation

Clone this repository into your DMS plugins directory (typically `~/.config/dms/plugins`):

```bash
mkdir -p ~/.config/dms/plugins
cd ~/.config/dms/plugins
git clone https://github.com/shazzaam7/DankAsusControl.git
```

Then restart DMS with `dms restart`, open **Settings → Plugins**, scan for plugins, and enable **ASUS Control Center**. Add the widget to your bar or dock layout to use the popout.

## Usage

Click the pill to open the popout. Sections appear only for features your hardware supports.

### GPU modes and reboot

Selecting a GPU mode writes the queued values to asusd. The change takes effect at shutdown, so a confirmation dialog appears asking **"Reboot to apply GPU mode?"**:

- **Reboot** reboots the system immediately.
- **Later** dismisses the dialog and leaves a badge in the popout header (and a dot on the bar pill) until you reboot or restart the shell.

If a write fails, the popout shows an error; a partially applied change is rolled back automatically where possible.

### Charge limit / one-shot

Use the slider to set the maximum charge level. **One-shot charging** temporarily lifts the limit for a single charge to 100%. When the firmware reports a charge mode, it is shown as a read-only chip.

### NVIDIA / CPU tuning

Tuning sliders appear when your device exposes the corresponding asusctl attributes. Each has a **default** button to reset it to `-1`.

> Profile tuning must be enabled for the current profile/power state before PPT (CPU/NVIDIA) values can be written. When tuning is off, the sliders are disabled and an **Enable profile tuning** button is shown — the plugin never enables it silently. This is a system-level change (EPP/fan behavior), so enable it deliberately.

### Keyboard backlight

Pick Off, Low, Med, or High. The active level is highlighted and verified by re-reading asusctl after the change.

### Control Center tile

The tile is available in DMS Control Center (a CompoundPill when the detail panel is enabled). It shows the active profile and battery percentage; clicking the tile cycles to the next supported profile, and the expanded panel lists all supported profiles.

## Settings

Open the plugin's settings from **Settings → Plugins** to control the theme colors, tray battery icon, and refresh interval (3 s / 5 s / 10 s, default 5 s). Hardware state is never persisted.
