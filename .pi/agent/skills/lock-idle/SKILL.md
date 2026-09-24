---
name: lock-idle
description: Use when working on the lock screen, idle handling, hypridle, suspend-before-lock issues, or the logind lid-switch chain. Load this skill whenever the trigger matches; the rules below are binding for that task.
---

# Lock / idle chain

Load this skill whenever the trigger matches; the rules below are binding for that task.

## The chain

**LOCK/IDLE CHAIN:** lid close → logind `HandleLidSwitch=suspend` (pure defaults, NO drop-ins) → hypridle `before_sleep_cmd = loginctl lock-session` → hypridle `lock_cmd` → `~/.config/ags/apps/greeter/dist/ags-lock.sh` (ext-session-lock via Gtk4SessionLock typelib shipped by `gtk4-layer-shell`, PAM `/etc/pam.d/astal-auth`, rebuilt by greeter `build-lock.sh`). hypridle 0.1.8 `inhibit_sleep = 3` takes the logind sleep DELAY lock at startup and releases it ONLY in `onLocked()` via `hyprland_lock_notifier_v1` (Hyprland 0.56.2 exports it) → lock surface not up within logind `InhibitDelayMaxSec` (default **5s**) = suspends UNLOCKED, logged as `Delay lock is active … but inhibitor timeout is reached`. Dock LockSession applet Sleep step holds logind `Inhibit(idle, ags-dock, block)`, persisted in `~/.config/ags/apps/dock/sleep-inhibit` and re-applied on dock start → hypridle `onIdled` skips every listener lacking `ignore_inhibit` (kills 300s idle lock + 330s dpms + 1800s suspend) but does NOT touch the lid path (`handleDbusLogin` spawns `lock_cmd` unconditionally). hypridle runs from `hypridle.service` (`systemctl --user start hypridle` in `hyprland.lua`, NOT a bare exec-once — logs land in `journalctl --user -u hypridle`; `graphical-session.target` is inactive so `WantedBy=` needs the explicit start). **hypridle has NO config hot-reload** — editing `hypridle.conf` without restarting leaves a stale `lock_cmd` in memory and lid close silently never locks. AGS lock renders in ~3s warm.
