---
name: bluetooth
description: Use when working on Bluetooth (Intel AX210, suspend/resume wedges, rfkill, bluetoothctl) or audio output routing (WirePlumber default nodes, Bluetooth-as-default-output). Load this skill whenever the trigger matches; the rules below are binding for that task.
---

# Bluetooth

Load this skill whenever the trigger matches; the rules below are binding for that task.

## Hardware + wedge history

**Bluetooth: Intel AX210** (USB `8087:0032`, usb 3-5; bluez 5.87; tlp 1.10.2). Recurring wedge = SUSPEND/RESUME (s2idle), not boot: HCI sync vs USB-teardown race (`Opcode 0x0c24 failed: -112`). Fixes applied: (1) `bluetooth-disable-before-sleep.service` (power off/on around suspend), (2) `/etc/modprobe.d/btusb.conf` `enable_autosuspend=n`, (3) tlp `USB_EXCLUDE_BTUSB=1`, (4) udev rule forcing `power/control=on` for 8087:0032 (the mechanism that works), (5) `/etc/sudoers.d/bluetooth-reload` NOPASSWD for `~/.local/bin/reload-bluetooth` (5 commands). systemd-rfkill restores saved soft-blocked state. **Script quirk:** `reload-bluetooth` leaves `Powered: no` — run `bluetoothctl power on` after. Verify the udev rule still exists in /etc/udev/rules.d/ before trusting fix (4).

## BT audio as default output

AUDIO: Bluetooth output devices are the DEFAULT sink — WirePlumber default-node policy `~/.config/wireplumber/wireplumber.conf.d/50-bt-default.conf`: all bluez_output.* sinks get priority.session 1200. On BT disconnect WirePlumber falls back to internal speakers. Do NOT stack pipewire-pulse switch-on-connect on top — one mechanism only.

## Per-device volume memory

Each device route's volume and mute are stored in `~/.local/state/wireplumber/default-routes` and restored when the route comes back (setting `device.restore-routes`), so a used device returns at the level it was left at — one level per device, no rule and no address anywhere. Stored route properties are applied AFTER a monitor rule writes its properties, so a rule can only reach a route with nothing stored: a rule seeds, it never overrides memory. A route with no stored volume takes `device.routes.default-sink-volume`, the cubic-scale amplitude — `0.008` is 20% as the desktop reports it, the shipped default `0.064` is 40% — set once in `~/.config/wireplumber/wireplumber.conf.d/10-default-sink-volume.conf`, where it applies to every device-route sink, wired included. Delete `~/.local/state/wireplumber/` (or run `wpctl reset`) to forget every remembered level; validating a changed fragment needs a wireplumber start, since the drop-ins are read at daemon start only.
