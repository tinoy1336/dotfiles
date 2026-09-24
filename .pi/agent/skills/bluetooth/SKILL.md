---
name: bluetooth
description: Use when working on Bluetooth (Intel AX210, suspend/resume wedges, rfkill, bluetoothctl) or audio output routing (WirePlumber default nodes, Bluetooth-as-default-output). Load this skill whenever the trigger matches; the rules below are binding for that task.
---

# Bluetooth

Load this skill whenever the trigger matches; the rules below are binding for that task.

## Hardware + wedge history

**Bluetooth: Intel AX210** (USB `8087:0032`, usb 3-5; bluez 5.87; tlp 1.10.2). Recurring wedge = SUSPEND/RESUME (s2idle), not boot: HCI sync vs USB-teardown race (`Opcode 0x0c24 failed: -112`). Fixes applied: (1) `bluetooth-disable-before-sleep.service` (power off/on around suspend), (2) `/etc/modprobe.d/btusb.conf` `enable_autosuspend=n`, (3) tlp `USB_EXCLUDE_BTUSB=1`, (4) udev rule forcing `power/control=on` for 8087:0032 (the mechanism that works), (5) `/etc/sudoers.d/bluetooth-reload` NOPASSWD for `~/.local/bin/reload-bluetooth` (5 commands). systemd-rfkill restores saved soft-blocked state. **Script quirk:** `reload-bluetooth` leaves `Powered: no` — run `bluetoothctl power on` after. Verify the udev rule still exists in /etc/udev/rules.d/ before trusting fix (4).

## BT audio as default output

AUDIO: user wants Bluetooth audio devices as the DEFAULT output — implemented via WirePlumber default-node policy `~/.config/wireplumber/50-bt-default.conf`: all bluez_output.* sinks get priority.session 1200 (AirPods volume special-case preserved). On BT disconnect WirePlumber falls back to internal speakers. Do NOT stack pipewire-pulse switch-on-connect on top — one mechanism only.
