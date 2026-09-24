#!/usr/bin/env bash
# launch-successor — start a successor pi session with the crew-worker environment
# stripped, so the successor is not born holding an identity another process owns.
#
# Why this exists: a successor spawned through the shell of the session that
# launches it inherits that session's crew binding. Launched from a WORKER's shell,
# the successor carries PI_SUBAGENT_CHILD / PI_SUBAGENT_PARENT_SESSION /
# PI_SUBAGENT_EXTENSION_BINDINGS / PI_INTERCOM_SESSION_ID, io-guard resolves that
# binding to an identity a live process already owns, and every write and edit the
# successor makes is refused for its whole life.
#
# The strip is by ENUMERATED NAME, never by prefix. `PI_SUBAGENT_PI_BINARY` (the
# wrapper a nested launch must keep using) and `PI_SUBAGENT_CACHE_RETENTION` are
# configuration, not identity, and a prefix strip would silently drop them.
#
# `~/.local/bin/pi-foreman` is the foreman-mode launcher and performs the same
# enumerated strip of those five identity names (it THEN exports PI_FOREMAN=1, which is
# what arms foreman mode in the fleet extension). One concept, one list: the five names
# are shared with that script and if the list changes, both must change with it, so they
# stay identical. This script exists for a successor that must NOT be armed as a foreman —
# a handoff into a plain session — so it strips exactly those five names PLUS PI_FOREMAN,
# and nothing else.
#
# Usage: launch-successor.sh <model> <handoff-path> [cwd]
#   <model>   provider/id, e.g. deepseek/deepseek-flash
#   <handoff> absolute path to the handoff markdown, passed as @file
#   [cwd]     project directory the handoff is about (default: current directory)
set -euo pipefail

MODEL=${1:?usage: launch-successor.sh <model> <handoff-path> [cwd]}
HANDOFF=${2:?usage: launch-successor.sh <model> <handoff-path> [cwd]}
CWD=${3:-$PWD}

unset PI_SUBAGENT
unset PI_SUBAGENT_CHILD
unset PI_SUBAGENT_PARENT_SESSION
unset PI_SUBAGENT_EXTENSION_BINDINGS
unset PI_INTERCOM_SESSION_ID

# PI_FOREMAN is MODE, not identity, and it is why this line exists: a successor launched
# from a WORKER's shell inherits PI_FOREMAN=1 from the session above it (the workers run
# under that session), and the fleet arms foreman mode from that variable, so the successor
# comes up armed for the wrong role. `PI_SUBAGENT_CHILD` is unset above and does not cover
# it. `pi-foreman` arms foreman mode EXPLICITLY (it exports PI_FOREMAN=1 after its own
# strip), so the inherited value must not decide it.
unset PI_FOREMAN

cd "$CWD"

# This script does NOT detach. It strips those names and execs pi, and the
# SPAWN FORM (SKILL.md step 4) is what keeps the successor alive: `setsid --fork nohup
# kitty …`, never wrapped in `timeout`. A detach inside this script cannot save a
# successor whose window's pty died, and a `setsid` on the pi invocation below would
# additionally take pi out of the pty's session (no terminal Ctrl-C, no kernel SIGWINCH
# on a resize), so it is not done here.
exec pi --model "$MODEL" "@$HANDOFF"
