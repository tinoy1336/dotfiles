#!/bin/sh
# Spawn the successor pi session for the AGS pre-first-commit polish handoff.
# Fired by ags-handoff-resume.timer (03:00 PDT, with a 03:10 retry slot).
#
# Idempotent: the retry slot must not open a SECOND session when the first one
# started fine — any live pi process already holding the handoff file is the
# successor, so exit quietly.
set -eu

HANDOFF="/home/tinoy/handoffs/2026-09-09-ags-polish-handoff.md"
CWD="/home/tinoy/.config/ags"
MODEL="deepseek-flash"

# The '@<path>' form is what the spawned pi command carries; matching the bare
# path would also hit any shell whose command line merely mentions it.
if pgrep -f "@$HANDOFF" >/dev/null 2>&1; then
  echo "successor session already running — nothing to do"
  exit 0
fi

export XDG_RUNTIME_DIR=/run/user/$(id -u)
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
export HYPRLAND_INSTANCE_SIGNATURE="$(ls -t /run/user/$(id -u)/hypr 2>/dev/null | head -1)"
export PATH="/home/tinoy/.local/bin:/usr/local/bin:/usr/bin:/bin"

cd "$CWD"
exec kitty --class handoff -e bash -lc "cd '$CWD' && exec pi --model '$MODEL' @'$HANDOFF'"
