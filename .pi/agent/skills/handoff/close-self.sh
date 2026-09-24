#!/usr/bin/env bash
# close-self — close the kitty window that a pi session is running in, from a process
# with no terminal of its own (a worker's tool shell has no controlling tty).
#
# WHY THE ESCAPE FRAME. kitty's remote-control client `kitty @` reaches a kitty instance
# over a socket (`listen_on`, which is NOT set on this machine) or over the controlling
# tty of the calling process. A worker's tool shell has neither: it runs in its own
# session with no controlling terminal, so `open /dev/tty` fails with ENXIO and
# `kitty @` reports `open /dev/tty`. kitty also parses the remote-control escape frame
# `ESC P @kitty-cmd <json> ESC \` out of the bytes a program writes to its terminal, and
# a write to the window's pty device is delivered to that parser the same way a program's
# own output is. So the close is a frame written to the pty that hosts the session.
#
# THE TARGET RESOLVES ITSELF. The frame must reach the pty of the session that is
# clocking out — the nearest `pi` ancestor of the process running this script, which is
# the session that hired it. That process's pty comes from /proc/<pid>/fd. A frame
# written to a pty that is not a kitty window's (another terminal, a plain ssh pty) does
# nothing at all, which is what the fallback and its log line exist for.
#
# `--fork` MUST NOT BE USED TO LAUNCH THIS SCRIPT: it reparents the helper to init before
# the parent walk runs. Plain `setsid … &` is enough (setsid(2) already puts the helper
# in a session of its own, out of reach of a process-group kill aimed at the caller).
#
# WRITE-ONLY BY DESIGN. The pty is shared with the session being closed: its read side
# carries that session's own terminal input and output, so this script never reads it.
# The frame asks for no reply (`no_response`) for the same reason — kitty's reply would
# be written back into the session's input stream. Success is the pi process exiting,
# checked against /proc.
#
# Usage: close-self.sh [options]
#   --pid PID              target pi pid (default: nearest `pi` ancestor of this process)
#   --pty PATH             pty of the target (default: resolved from /proc/<pid>/fd)
#   --window N             select the window by `match id:N` instead of `self:true`
#   --delay SECONDS        wait before closing (default 2; the final response flushes first)
#   --confirm SECONDS      how long to give the close before the fallback (default 8)
#   --protocol-version M.m.p   frame protocol version (default: read from `kitty --version`)
#   --kill-fallback        arm `kill -TERM <pid>` when the frame has not ended pi (default)
#   --no-kill-fallback     disable that arm
#   --dry-run              print the resolved target and the frame, write nothing
#
# Exit codes: 0 pi is gone · 1 usage error · 2 target invalid / version unreadable ·
# 3 frame written but pi survived (window still up).
#
# The helper prints its OWN pid to stdout and writes `close-self: helper pid <pid>` to the
# log before the delay: that process is what to kill to cancel a pending close.
set -euo pipefail

usage() {
	sed -n '2,44p' "$0" >&2
	exit 1
}

PID=""
PTY=""
WIN=""
DELAY=2
CONFIRM=8
KILL_FALLBACK=1
DRY_RUN=0
PROTOCOL_VERSION=""

while [[ $# -gt 0 ]]; do
	case $1 in
		--pid) [[ $# -ge 2 ]] || usage; PID=$2; shift 2 ;;
		--pty) [[ $# -ge 2 ]] || usage; PTY=$2; shift 2 ;;
		--window) [[ $# -ge 2 ]] || usage; WIN=$2; shift 2 ;;
		--delay) [[ $# -ge 2 ]] || usage; DELAY=$2; shift 2 ;;
		--confirm) [[ $# -ge 2 ]] || usage; CONFIRM=$2; shift 2 ;;
		--protocol-version) [[ $# -ge 2 ]] || usage; PROTOCOL_VERSION=$2; shift 2 ;;
		--kill-fallback) KILL_FALLBACK=1; shift ;;
		--no-kill-fallback) KILL_FALLBACK=0; shift ;;
		--dry-run) DRY_RUN=1; shift ;;
		*) echo "close-self: unknown argument: $1" >&2; usage ;;
	esac
done

log() { printf 'close-self: %s\n' "$*" >&2; }
is_pi() { [[ "$(cat /proc/$1/comm 2>/dev/null || true)" == "pi" ]]; }

# Resolve the target BEFORE any delay: a detached helper's parent chain is intact only
# while the shell that started it is still alive.
if [[ -z $PID ]]; then
	probe=$$
	for _ in $(seq 1 40); do
		probe=$(awk '{print $4}' "/proc/$probe/stat" 2>/dev/null) || break
		[[ -n ${probe:-} && $probe != 0 ]] || break
		if is_pi "$probe"; then PID=$probe; break; fi
	done
	if [[ -z $PID ]]; then
		log "refusing: no 'pi' ancestor found; pass --pid with the session's own pi pid"
		exit 2
	fi
fi

[[ $PID =~ ^[0-9]+$ ]] || { echo "close-self: --pid must be numeric, got '$PID'" >&2; exit 1; }

if [[ ! -d /proc/$PID ]]; then
	log "pid $PID is already gone; nothing to close"
	exit 0
fi

if ! is_pi "$PID"; then
	log "refusing: pid $PID is not pi (comm='$(cat /proc/$PID/comm 2>/dev/null || echo '?')')"
	exit 2
fi

# argv[0] only: the cmdline is NUL-separated, so reading the whole file as one string
# would compare the LAST argument (the handoff file for `pi --model M @file`).
argv0=""
read -r -d '' argv0 <"/proc/$PID/cmdline" 2>/dev/null || true
if [[ "$(basename "${argv0:-}")" != "pi" ]]; then
	log "refusing: pid $PID does not run the pi command line"
	exit 2
fi

if [[ -z $PTY ]]; then
	for fd in /proc/$PID/fd/*; do
		target=$(readlink "$fd" 2>/dev/null || true)
		if [[ $target =~ ^/dev/pts/[0-9]+$ ]]; then
			PTY=$target
			break
		fi
	done
fi

if [[ -z $PTY ]]; then
	log "refusing: pid $PID has no pty (not a terminal session); pass --pty to force one"
	exit 2
fi

# The frame's version field is the client protocol version. A version GREATER than the
# running instance's makes kitty refuse the whole command, so it is read off the running
# instance rather than copied from anywhere; an unreadable version is a refusal, never a
# guess (pass --protocol-version to state one explicitly).
if [[ -z $PROTOCOL_VERSION ]]; then
	if version=$(kitty --version 2>/dev/null) && [[ $version =~ ^kitty\ ([0-9]+\.[0-9]+\.[0-9]+) ]]; then
		PROTOCOL_VERSION=${BASH_REMATCH[1]}
	else
		log "refusing: could not read 'kitty --version'; pass --protocol-version MAJOR.MINOR.PATCH"
		exit 2
	fi
fi

[[ $PROTOCOL_VERSION =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || {
	echo "close-self: --protocol-version must be MAJOR.MINOR.PATCH, got '$PROTOCOL_VERSION'" >&2
	exit 1
}
V_MAJOR=${BASH_REMATCH[1]}
V_MINOR=${BASH_REMATCH[2]}
V_PATCH=${BASH_REMATCH[3]}

if [[ -n $WIN ]]; then
	[[ $WIN =~ ^[0-9]+$ ]] || { echo "close-self: --window must be numeric, got '$WIN'" >&2; exit 1; }
	PAYLOAD="{\"match\":\"id:$WIN\"}"
else
	# `self` selects the window the frame came from — on this route that is the target.
	PAYLOAD='{"self":true}'
fi

FRAME=$(printf '{"cmd":"close-window","version":[%s,%s,%s],"no_response":true,"payload":%s}' \
	"$V_MAJOR" "$V_MINOR" "$V_PATCH" "$PAYLOAD")

printf 'close-self: helper pid %s\n' "$$"
log "helper pid $$: target pid $PID pty $PTY payload $PAYLOAD delay ${DELAY}s"
if [[ $DRY_RUN -eq 1 ]]; then
	log "dry-run: frame that would be written: ESC P @kitty-cmd $FRAME ESC \\"
	exit 0
fi

sleep "$DELAY"

if [[ ! -d /proc/$PID ]]; then
	log "pid $PID gone before the close was written"
	exit 0
fi

close_frame() {
	python3 - "$PTY" "$FRAME" <<'PY'
import os, sys
pty, frame = sys.argv[1], sys.argv[2]
# O_NOCTTY: never let this write make the pty the caller's controlling terminal.
fd = os.open(pty, os.O_WRONLY | os.O_NOCTTY | os.O_NONBLOCK)
try:
    os.write(fd, b'\x1bP@kitty-cmd' + frame.encode() + b'\x1b\\')
finally:
    os.close(fd)
PY
}

if sub=$(close_frame 2>&1); then
	log "close frame written to $PTY"
else
	log "frame write failed: $sub"
fi

deadline=$((CONFIRM * 4))
while [[ $deadline -gt 0 && -d /proc/$PID ]]; do
	sleep 0.25
	deadline=$((deadline - 1))
done

if [[ ! -d /proc/$PID ]]; then
	log "closed: pid $PID is gone, window down"
	exit 0
fi

if [[ $KILL_FALLBACK -eq 1 ]]; then
	log "frame did not end pid $PID; falling back to kill -TERM (this leaves the window empty)"
	kill -TERM "$PID" 2>/dev/null || true
	sleep 3
	if [[ -d /proc/$PID ]]; then
		log "STILL ALIVE after TERM: pid $PID — needs a manual close"
		exit 3
	fi
	log "fallback ended pid $PID; the kitty window is left empty"
	exit 0
fi

log "frame written but pid $PID survived (fallback disabled); the window is still up"
exit 3
