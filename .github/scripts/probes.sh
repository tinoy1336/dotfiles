#!/bin/sh
# probes — run the probes that decide their own fixtures.
#
# A probe exists so a guard that rots is caught before it is trusted, and a probe
# nothing runs is inert. This is the one place they are invoked, so the run a
# reader makes and the run the job makes are the same command line.
#
# Everything here builds what it needs — a scratch home, a state directory of its
# own, a stub named for the command it must not reach — so a runner with no
# compositor, no injection tool and no credential store can still decide them.
# Two probes are deliberately NOT here, and neither is skipped for convenience:
#
#   pi-cost-probe    imports the cost extension from the installed agent tree
#                    (`~/.pi/agent/extensions/deepseek-cost.ts`), and
#   pi-guard-probe   imports the installed command-guard package
#                    (`~/.pi/agent/npm/node_modules/@tinoy/pi-command-guard/`).
#
# Neither path is carried by this repository, so both would report on a runner
# that has no agent tree rather than on their subject; they are run by hand where
# that tree exists. `cli-keys-probe` reads its fixture with `jq`, which the probe
# itself refuses to run without.
#
# Each probe runs under a timeout, so a probe that waits on a device or a socket
# fails this run instead of holding it, and any probe that fails fails this script.
#
# Usage: probes.sh
#
# The probes take the tool they check from an environment override, because the
# tracked script and the tool it checks are not installed under $HOME on a runner.
set -eu

# A relative path named on the command line would be resolved against an
# inherited CDPATH otherwise.
unset CDPATH

here=$(cd -- "$(dirname -- "$0")" && pwd)
root=$(cd -- "$here/../.." && pwd)

# A probe that could not be bounded is a probe that can hang the run, and a run
# that hangs reads like a run that passed until the job times out.
command -v timeout >/dev/null 2>&1 || {
  echo "probes: no timeout command — a probe could hang this run, so it did not run" >&2
  exit 2
}

probe_timeout=${PROBE_TIMEOUT:-90}
ran=0

run_probe() { # <label> <variable the probe reads> <probe> <tool it checks>
	label=$1
	variable=$2
	probe=$3
	tool=$4
	if [ ! -x "$probe" ]; then
		echo "probes: $probe is missing or not executable — NOTHING RAN" >&2
		exit 2
	fi
	if [ ! -f "$tool" ]; then
		echo "probes: $label checks $tool, which is not in this checkout" >&2
		exit 2
	fi
	echo "probes: $label"
	env "$variable=$tool" timeout "$probe_timeout" "$probe"
	ran=$((ran + 1))
}

run_probe "host-apply-probe" HOST_APPLY_PROBE_TOOL \
	"$root/.local/bin/host-apply-probe" "$root/.local/bin/host-apply"
run_probe "ws-cycle-probe" WS_CYCLE_PROBE_TOOL \
	"$root/.config/hypr/ws-cycle-probe.sh" "$root/.config/hypr/ws-cycle.sh"
run_probe "cli-keys-probe" CLI_KEYS_PROBE_TOOL \
	"$root/.local/bin/cli-keys-probe" "$root/.local/bin/cli-keys"
run_probe "inject-probe" INJECT_PROBE_TOOL \
	"$root/.local/bin/inject-probe" "$root/.local/bin/inject"

echo "probes: $ran probe(s) passed"
