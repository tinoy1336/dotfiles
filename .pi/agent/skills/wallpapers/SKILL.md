---
name: wallpapers
description: Use when working on wallpapers, wallpaper sync (Proton Drive), the wallpaper rotation timer, or the awww wallpaper daemon. Load this skill whenever the trigger matches; the rules below are binding for that task.
---

# Wallpapers

Load this skill whenever the trigger matches; the rules below are binding for that task.

## Sync machinery

**Wallpaper sync (ON-DEMAND):** `~/wallpapers` ↔ Proton Drive `/my-files/Wallpapers` via `~/.local/bin/wallpapers-sync`: `pull [--apply]` (cloud→local), `push` (local→cloud, uploads changed only), `apply` (random local PNG via awww fade + greeter copy). Uses `proton-drive` CLI 0.7.0 (non-interactive). proton-drive-sync + proton-wallpapers FULLY REMOVED — no background sync. Rotation `wallpaper-cycle.timer` (10min) → `wallpapers-sync apply`; login apply `wallpapers-apply.service`. Display = **awww** (`awww`/`awww-daemon`; the `swww` name is GONE; daemon unit `awww-daemon.service` runs in FOREGROUND, `Environment=WAYLAND_DISPLAY=wayland-1`).

## hyprpaper

hyprpaper 0.8.4 — UNUSED (replaced by awww; kept as fallback only).
