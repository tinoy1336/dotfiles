#!/usr/bin/env bash
# ws-cycle-probe — fixture table for ws-cycle.sh's style index.
#
# ws-cycle.sh keeps its position in a state file and steps through the style list
# with a modulo, so the arithmetic is invisible until it is wrong: a wrap that
# goes one past the end draws no animation, a stored index that is no longer in
# the list is only corrected by the modulo, and the negative side needs its own
# correction because a shell's modulo keeps the sign. A broken step is also
# SILENT — the command still exits 0, the notification still renders, and the
# only difference is which transition the compositor was asked for.
#
# The prober drives the real script through its own argument and state paths and
# reads the style it asked for. Nothing reaches the compositor or the desktop:
# `hyprctl` and `notify-send` are stubs that record their own arguments, and the
# state file lives under a scratch home.
#
# Usage: ws-cycle-probe [--verbose]
# Exit:  0 = every fixture matches, 1 = a fixture's outcome changed,
#        2 = the probe itself failed.
set -uo pipefail

TOOL="${WS_CYCLE_PROBE_TOOL:-$HOME/.config/hypr/ws-cycle.sh}"
VERBOSE=0
[ "${1:-}" = "--verbose" ] && VERBOSE=1

[ -x "$TOOL" ] || {
  printf 'ws-cycle-probe: %s is not executable — THE PROBE DID NOT RUN\n' "$TOOL" >&2
  exit 2
}

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/ws-cycle-probe.XXXXXX")"
cleanup() {
  case "$(readlink -f "$SCRATCH")" in
  "${TMPDIR:-/tmp}"/ws-cycle-probe.*) rm -rf "$SCRATCH" ;;
  esac
}
trap cleanup EXIT

STUB="$SCRATCH/stub"
HOME_DIR="$SCRATCH/home"
mkdir -p "$STUB" "$HOME_DIR/.cache"

# Both commands the script reaches past itself with are stubbed: the compositor
# call is what the probe reads, and the notification must not reach the desktop.
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/dispatched"\nexit 0\n' "$SCRATCH" > "$STUB/hyprctl"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/notified"\nexit 0\n' "$SCRATCH" > "$STUB/notify-send"
chmod +x "$STUB/hyprctl" "$STUB/notify-send"
PATH="$STUB:$PATH"
export PATH

STATE="$HOME_DIR/.cache/hypr-ws-cycle"
STYLE_COUNT=7

pass=0
fail=0
note() {
  if [ "$VERBOSE" = 1 ]; then printf '       %s\n' "$*"; fi
}

# case <name> <stored state|NONE> <argument|-> <want-style> <want-index>
case_step() {
  local name="$1" stored="$2" arg="$3" want_style="$4" want_index="$5"
  local out status dispatched index style
  rm -f "$STATE"
  [ "$stored" = NONE ] || printf '%s\n' "$stored" > "$STATE"
  : > "$SCRATCH/dispatched"
  : > "$SCRATCH/notified"

  if [ "$arg" = "-" ]; then
    out="$(HOME="$HOME_DIR" "$TOOL" 2>&1)"
  else
    out="$(HOME="$HOME_DIR" "$TOOL" "$arg" 2>&1)"
  fi
  status=$?

  if [ "$status" != 0 ]; then
    printf 'FAIL  %s :: exit %s, wanted 0\n' "$name" "$status"
    printf '%s\n' "$out" | sed 's/^/       | /'
    fail=$((fail + 1))
    return 0
  fi

  dispatched="$(cat "$SCRATCH/dispatched" 2>/dev/null)"
  case "$dispatched" in
  *"style = \"$want_style\""*) ;;
  *)
    printf 'FAIL  %s :: asked the compositor for something other than %s\n' "$name" "$want_style"
    printf '       | %s\n' "$dispatched"
    fail=$((fail + 1))
    return 0
    ;;
  esac

  index="$(cat "$STATE" 2>/dev/null)"
  if [ "$index" != "$want_index" ]; then
    printf 'FAIL  %s :: stored index %s, wanted %s\n' "$name" "${index:-<empty>}" "$want_index"
    fail=$((fail + 1))
    return 0
  fi

  pass=$((pass + 1))
  printf 'ok    %s\n' "$name"
  note "style=$want_style index=$want_index"
}

case_step "no state file steps to the second style" NONE 1 slidevert 1
case_step "the first style steps forward" 0 1 slidevert 1
case_step "the last style wraps to the first" 6 1 slide 0
case_step "the first style wraps backward to the last" 0 -1 "slidefadevert 20%" 6
case_step "a stored index past the end is folded back into the list" 99 1 fade 2
case_step "a negative stored index is corrected rather than indexed" -3 1 slidefadevert 5
case_step "no argument steps forward" 4 - slidefadevert 5

# The step must be one step: a run that never writes the state would still draw a
# style, so the file is checked above, and the notification is checked here to
# confirm the script reached its own reporting path rather than a compositor stub
# that swallowed a failure.
if [ -s "$SCRATCH/notified" ]; then
  printf 'ok    the run reports the style it chose\n'
  pass=$((pass + 1))
else
  printf 'FAIL  a run dispatched without reporting\n'
  fail=$((fail + 1))
fi

# A style list longer or shorter than the index the script folds into would keep
# the wrap correct and the meaning wrong, so the count the probe folds with is
# checked against the script's own list.
declared="$(grep -c '^STYLES=' "$TOOL" 2>/dev/null)"
if [ "$declared" = 1 ]; then
  listed="$(sed -n 's/^STYLES=(\(.*\))$/\1/p' "$TOOL" | grep -o '"[^"]*"' | wc -l | tr -d ' ')"
  if [ "$listed" = "$STYLE_COUNT" ]; then
    printf 'ok    the style list still holds %s entries\n' "$STYLE_COUNT"
    pass=$((pass + 1))
  else
    printf 'FAIL  the style list holds %s entries, and this probe folds with %s\n' "$listed" "$STYLE_COUNT"
    fail=$((fail + 1))
  fi
else
  printf 'FAIL  no single STYLES= line in %s — this probe folds against a list it can no longer read\n' "$TOOL"
  fail=$((fail + 1))
fi

printf 'ws-cycle-probe: %s fixture(s) matched, %s changed\n' "$pass" "$fail"
[ "$fail" = 0 ] || exit 1
exit 0
