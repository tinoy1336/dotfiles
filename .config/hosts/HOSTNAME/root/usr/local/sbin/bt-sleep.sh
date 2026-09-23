#!/usr/bin/env bash
# bt-sleep.sh start|stop — preserve the Bluetooth powered state across suspend.
# The old disable-before-sleep service ran `bluetoothctl power on` UNCONDITIONALLY
# on wake, re-enabling Bluetooth the user had switched off. Pre-sleep state is
# recorded in /run (tmpfs) and restored on wake; a dead daemon = "off".
set -euo pipefail
STATE=/run/bt-sleep-state
case "${1:-}" in
  start)
    if bluetoothctl show 2>/dev/null | grep -q '^[[:space:]]*Powered: yes'; then
      echo on > "$STATE"
    else
      echo off > "$STATE"
    fi
    bluetoothctl power off >/dev/null 2>&1 || true
    ;;
  stop)
    if [ -f "$STATE" ] && [ "$(cat "$STATE" 2>/dev/null)" = on ]; then
      bluetoothctl power on >/dev/null 2>&1 || true
    fi
    ;;
esac
