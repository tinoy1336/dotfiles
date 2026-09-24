---
name: asus-hardware
description: Use when touching tablet mode (SW_TABLET_MODE), the ASUS EC/battery fuel gauge, or ASUS convertible hardware quirks (touchscreen, sensors, modprobe options). Load this skill whenever the trigger matches; the rules below are binding for that task.
---

# ASUS hardware

Load this skill whenever the trigger matches; the rules below are binding for that task.

## Convertible / tablet mode

**ASUS convertible (2-in-1):** tablet mode auto-detectable (`/etc/modprobe.d/asus-nb-wmi.conf` `tablet_mode_sw=2`; DSTS 0x60062). The dock's auto mode reads SW_TABLET_MODE via EVIOCGSW — needs user in `input` group AND a systemd --user manager restart (lingering manager keeps pre-usermod groups → reboot needed). Manual override: `ags -i shell request "dock tablet set on|off|auto"` (dev island: `ags -i dock request ...`). Open applets auto-close after `timing.tabletCloseMs` (3000) while on. Touchscreen elan9008:00-04f3:4359. Workspace switching off-tablet: touchscreen edge swipe (hyprland.lua `gestures:workspace_swipe_touch`), trackpad 3-finger, dock workspaces applet (11-step slider; SUPER+0 = ws 10, SUPER+MINUS = ws 11), hyprgrass v0.8.2 (built by hyprpm into `/var/cache/hyprpm/tinoy/hyprgrass/hyprgrass.so`, 3-finger touchscreen swipe = ws cycle; loaded at boot by `~/.config/hypr/hyprgrass-load.sh` — 0.56 has NO `plugin =` keyword).

## Sensors — never address an IIO device by index

**IIO device numbering is NOT stable across boots** (enumeration order shifts; on 2026-09-17 the screen accelerometer `accel_3d` moved from `iio:device2` to `iio:device3` while the ambient-light sensor `als` took `device2`). Resolve sensors by the `name` attribute instead — `prox` (×2, USB) / `als` / `accel_3d` expose no `in_accel_*` files, so a stale index raises on every read. `~/.local/bin/auto-rotate` (`auto-rotate.service`, started by hyprland.lua) and `~/.config/ags/common/tablet/watchdog.ts` (`findAccelDevice`) both discover `accel_3d` by name. Symptom of a stale index: journal spams `[auto-rotate] tablet=False` every 0.5 s and the display never rotates in tablet mode.

## EC fuel gauge

**ASUS EC fuel-gauge desync:** EC can freeze the fuel gauge (`energy_now` stuck at `energy_full`, `capacity` 100, `status` Discharging with live `power_now`) → every consumer shows frozen %. Plain `reboot` resets it (~30s). Not overcharge (voltage normal). Full discharge→charge cycle = calibration cure.
