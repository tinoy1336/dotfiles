#!/usr/bin/env bash
# Load the hyprgrass touchscreen-gesture plugin at hyprland startup and apply
# its settings + gesture binds.
#
# Not config lines: Hyprland 0.56 removed the `plugin =` keyword, the plugin only
# loads after config parse, and `hyprctl keyword` is locked — so the plugin is
# loaded at runtime and everything else goes through `hyprctl eval`.
#
# PLUGIN is hyprpm's own build output (sudo hyprpm add); loading it directly
# avoids a hyprpm dependency at boot.

PLUGIN=/var/cache/hyprpm/tinoy/hyprgrass/hyprgrass.so

hyprctl plugin load "$PLUGIN" >/dev/null 2>&1 || true   # already loaded on re-runs
sleep 0.2  # let the plugin register its options/dispatchers

# sensitivity 4.0 is the recommendation for tablet screens
hyprctl eval "hl.config({ plugin = { hyprgrass = { sensitivity = 4.0, long_press_delay = 400 } } })" >/dev/null 2>&1 || true

# 3-finger swipe anywhere on the touchscreen = 1:1 workspace swipe; hyprgrass's
# duplicate-guard rejects a second bind of the same gesture.
hyprctl eval "hl.plugin.hyprgrass.gesture({ pattern = { kind = 'swipe', fingers = 3, direction = 'horizontal' }, action = 'workspace' })" >/dev/null 2>&1 || true
