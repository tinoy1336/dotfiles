#!/usr/bin/env bash
# ~/.config/hypr/hyprgrass-load.sh
# Load the hyprgrass touchscreen-gesture plugin at hyprland startup and apply
# its settings + gesture binds.
#
# Why a script instead of config lines: Hyprland 0.56 removed the `plugin =`
# config keyword (hyprpm owns loading), and the plugin can only load AFTER
# config parse (hyprpm reload / runtime load), so anything referencing it in
# hyprland.lua at parse time errors. `hyprctl keyword` is also locked ("use
# eval" for non-legacy parsers) — so: runtime `plugin load` + `hyprctl eval`
# (the lua-in-compositor API, same mechanism ws-cycle.sh uses).
#
# The plugin is built by `sudo hyprpm add` into /var/cache/hyprpm/tinoy/ and
# is enabled in hyprpm's state (hyprpm reload -n would also load it); the
# direct load here avoids the hyprpm dependency at boot.

PLUGIN=/var/cache/hyprpm/tinoy/hyprgrass/hyprgrass.so

hyprctl plugin load "$PLUGIN" >/dev/null 2>&1 || true   # already loaded on re-runs
sleep 0.2  # let the plugin register its options/dispatchers

# Settings (docs: sensitivity 4.0 is the recommendation for tablet screens).
hyprctl eval "hl.config({ plugin = { hyprgrass = { sensitivity = 4.0, long_press_delay = 400 } } })" >/dev/null 2>&1 || true

# 3-finger swipe anywhere on the touchscreen = 1:1 workspace swipe
# (hyprgrass's own duplicate-guard errors if this is somehow already bound).
hyprctl eval "hl.plugin.hyprgrass.gesture({ pattern = { kind = 'swipe', fingers = 3, direction = 'horizontal' }, action = 'workspace' })" >/dev/null 2>&1 || true
