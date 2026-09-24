---
name: hyprland-plugins
description: Use when a Hyprland version update, plugin rebuild (hyprpm), or the hyprgrass plugin is involved. Load this skill whenever the trigger matches; the rules below are binding for that task.
---

# Hyprland plugins

Load this skill whenever the trigger matches; the rules below are binding for that task.

## hyprpm/hyprgrass

**hyprpm/hyprgrass:** hyprgrass.so MUST be rebuilt on Hyprland updates (API hash check → 5s amber notif). `~/.local/bin/yup` runs `hyprpm update` after version change. hyprpm refuses root + shells out to `sudo` for cache ops — narrow shim `~/.local/bin/sudo` runs those directly (everything else → `/usr/bin/sudo`). If "Failed to run a superuser cmd"/header mismatch: check shim or dir modes (headersRoot 755).
