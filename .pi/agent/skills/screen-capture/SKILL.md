---
name: screen-capture
description: Use when the user asks for any screenshot, screengrab, or screen-region capture — includes window grabs, grim/hyprpicker region shots, and the machine's Print-key pipeline. Load this skill whenever the trigger matches; the rules below are binding for that task.
---

# Screen capture

Load this skill whenever the trigger matches; the rules below are binding for that task.

## Permission protocol

**SCREENSHOTS — STANDING PERMISSION (user 2026-09-06):** the user grants full machine access + screenshots effective immediately — NO per-instance permission asks, including mid-task. Keep the hygiene: resolve real geometry (`hyprctl clients -j`), `grim -g` the exact rect only, delete the file after use; don't browse the screen without a task reason. If occluded, ask the user for a shot.

## Keys and pipeline quirks

**Screenshot keys (ASUS firmware):** Fn+F11 emits Print. `Print` = region capture routed INTO the live AGS instance that hosts the dock's screen grab applet: `common/shell/ensure-screengrab.sh` → `tinshell-route.sh --no-start dock screengrab capture still select`. It refuses to cold-start (exit 2 → a dual-channel notice via `notify-failed.sh`, because the AGS notification daemon is one of the things down in that case), so the key fails fast instead of paying a bundle rebuild. The capture runs in-process on purpose: the notification's **Annotate** action is dispatched through an in-process handler, so a capture taken anywhere else would raise a button that goes nowhere. Storage dir + name template come from the dock's `screengrab` config, and the Print path also copies the shot to the clipboard. `~/.local/bin/screenshot-region` is GONE — do not re-create it; the pipeline lives below.

**FREEZE:** `apps/dock/screengrab/capture.ts` `selectGeo()` selects on a frozen frame — hyprpicker paints a still copy of every output on the overlay layer (`-r -z -d -q`), slurp selects on top of that still, and grim captures the frozen composite. **FIRST-CLICK FIX:** hyprctl layers lists layer surfaces at CREATION, not map — `alpha` flips 0→1 only on real map; and slurp+hyprpicker are both EXCLUSIVE-keyboard layer surfaces — Hyprland pins pointer+keyboard focus to whichever maps LAST. The code therefore pid-filters `hyprctl layers -j` and waits for every picker surface to reach `alpha >= 1` before slurping; the picker stays mapped until grim finishes (killing it first races the overlay fade-out and blends the frozen frame with the live one), then `endFreeze()` escalates SIGTERM → SIGKILL (hyprpicker ignores SIGTERM while stuck in its screencopy loop) with a 60s guard against a stranded overlay. A bare click soaked by a late map returns a 1×1 box — re-armed, never exported. hyprpicker `-z` = no-zoom, NOT freeze; the freeze is inherent to it, layer namespace `hyprpicker` and no layerrule matches it (so nothing blurs the frozen frame). **NO SHIFT+Print / fullscreen bind** — `Print` is the only screenshot key. **grim quirk: NO output arg = timestamped file in $GRIM_DEFAULT_DIR→$XDG_PICTURES_DIR (NOT stdout)** — stdout requires explicit `-` (same as `grim -g - -`).
