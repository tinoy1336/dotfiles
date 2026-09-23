#!/usr/bin/env bash
# Workspace transition style cycler (Hyprland 0.56, Lua config)
# Usage: ws-cycle.sh [1|-1]   (direction; default forward)
STYLES=("slide" "slidevert" "fade" "slidefade" "slidefade 20%" "slidefadevert" "slidefadevert 20%")
STATE="$HOME/.cache/hypr-ws-cycle"

dir="${1:-1}"
idx=$(cat "$STATE" 2>/dev/null || echo 0)
n=${#STYLES[@]}
idx=$(( (idx + dir) % n ))
if [ "$idx" -lt 0 ]; then idx=$(( idx + n )); fi
echo "$idx" > "$STATE"

style="${STYLES[$idx]}"
hyprctl eval "hl.animation({ leaf = \"workspaces\", enabled = true, speed = 1.94, bezier = \"wsRigid\", style = \"$style\" })"
notify-send -t 2000 "workspace transition: $style"
