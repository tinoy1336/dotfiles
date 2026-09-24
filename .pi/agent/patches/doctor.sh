#!/usr/bin/env bash
# pi toolchain doctor: is this pi install healthy after a package rewrite?
#
# Three checks, in the order the failures actually happened:
#
#   HOST    — which `pi` is on PATH, resolved through its symlink to the package that
#             owns it, plus that package's version. The failure class this names is two
#             installs with two owners: the host pi AND the peers under
#             ~/.pi/agent/npm/node_modules resolve separately, so both the path and the
#             version are reported instead of a bare "pi is installed".
#   RUNNER  — the async runner's module graph, imported in this Node through the same
#             preload the spawned child uses. The child runs
#             `node --import <pkg>/runner-peer-preload.mjs <pkg>/src/runs/background/subagent-runner.js <cfg>`;
#             importing that module the same way fails here when a peer export the
#             installed @earendil-works/pi-ai no longer provides — the
#             `createInitialSystemMessage` breakage, which killed every async run at
#             import while `fleet hire` still answered ok. subagent-runner.js guards its
#             own entrypoint (isRunnerEntrypoint), so importing it starts no run. The
#             declared peer RANGE is ADVISORY only and never decides health:
#             pi-subagents declares @earendil-works/pi-ai >=0.80.0, a range the
#             functionally incompatible peer satisfies.
#   PATCHES — every marker in managed-patches.conf re-grepped against the INSTALLED
#             files, entry by entry, the same test apply-patches.sh decides apply state
#             with.
#
# Healthy = exit 0, no output, no notification: this runs after every package rewrite
# and at every login, so it must be invisible while things are fine. Unhealthy = the
# failing check on stdout, ONE notification naming the check and the single command
# that fixes it, exit 1. `-v` prints the whole report (checks, resolved paths, versions,
# advisory warnings) for a hand run.
#
# Env: PI_DOCTOR_MANIFEST, PI_DOCTOR_SUB_PKG and PI_DOCTOR_PI_BIN relocate the inputs;
# PI_DOCTOR_NO_NOTIFY=1 silences the notification and prints it instead.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${PI_DOCTOR_MANIFEST:-$ROOT/managed-patches.conf}"
SUB_PKG="${PI_DOCTOR_SUB_PKG:-/home/tinoy/.pi/agent/npm/node_modules/pi-subagents}"
PI_BIN="${PI_DOCTOR_PI_BIN:-}"
APPLIER="$ROOT/apply-patches.sh"

verbose=0
[ "${1:-}" = "-v" ] && verbose=1

report=""
warnings=""
failures=""

report_line() { report="$report$1"$'\n'; }
warn_line() { warnings="$warnings$1"$'\n'; }
fail() { # check-name detail
	failures="$failures$1"$'\n'
	report_line "FAIL  $1: $2"
}
first_failure() { printf '%s' "${failures%%$'\n'*}"; }

notify() { # title body
	if [ -n "${PI_DOCTOR_NO_NOTIFY:-}" ]; then
		return 0
	fi
	command -v notify-send >/dev/null 2>&1 || return 0
	notify-send -a pi-doctor -u critical "$1" "$2" >/dev/null 2>&1 || true
}

# --- HOST: the pi on PATH, resolved to the package that owns it ------------------
check_host() {
	if [ -z "$PI_BIN" ]; then
		PI_BIN="$(command -v pi 2>/dev/null || true)"
	fi
	if [ -z "$PI_BIN" ]; then
		fail HOST "no pi on PATH"
		return
	fi
	local real host
	real="$(readlink -f "$PI_BIN" 2>/dev/null || printf '%s' "$PI_BIN")"
	host="$(PI_DOCTOR_HOST_BIN="$real" timeout 20 node -e '
const fs = require("node:fs"), path = require("node:path");
let dir = path.dirname(process.env.PI_DOCTOR_HOST_BIN), found = null;
while (dir && dir !== "/") {
	const f = path.join(dir, "package.json");
	if (fs.existsSync(f)) {
		try {
			const j = JSON.parse(fs.readFileSync(f, "utf8"));
			if (j.name === "@earendil-works/pi-coding-agent") { found = j; break; }
		} catch {}
	}
	dir = path.dirname(dir);
}
console.log(found ? `${found.name} ${found.version}` : "no owning @earendil-works/pi-coding-agent package");
' 2>/dev/null)"
	if [ -z "$host" ]; then
		fail HOST "cannot read the package that owns $real"
		return
	fi
	report_line "HOST    pi = $PI_BIN -> $real ($host)"
}

# --- RUNNER: import the async runner's module graph the way the child loads it ----
check_runner() {
	local runner="$SUB_PKG/src/runs/background/subagent-runner.js" out rc line
	if [ ! -f "$runner" ]; then
		fail RUNNER "async runner source absent: $runner"
		return
	fi
	out="$(PI_DOCTOR_SUB_PKG="$SUB_PKG" timeout 40 node --import "file://$SUB_PKG/runner-peer-preload.mjs" --input-type=module - 2>&1 <<'NODE'
const fs = await import("node:fs");
const path = await import("node:path");
const { pathToFileURL } = await import("node:url");
const pkg = process.env.PI_DOCTOR_SUB_PKG;
const runner = path.join(pkg, "src/runs/background/subagent-runner.js");
// Node's own bare-specifier resolution, walked by hand: createRequire(...).resolve
// answers ERR_PACKAGE_PATH_NOT_EXPORTED for a peer whose exports map has no root entry,
// and the point here is the path the child's import actually takes.
let peerPath = "UNRESOLVED", peerVersion = "", declared = "";
{
	let dir = path.dirname(runner);
	while (dir && dir !== "/") {
		const candidate = path.join(dir, "node_modules", "@earendil-works", "pi-ai", "package.json");
		if (fs.existsSync(candidate)) {
			try { peerVersion = JSON.parse(fs.readFileSync(candidate, "utf8")).version ?? ""; } catch {}
			peerPath = candidate.replace(/\/package\.json$/, "");
			break;
		}
		dir = path.dirname(dir);
	}
}
try { declared = JSON.parse(fs.readFileSync(path.join(pkg, "package.json"), "utf8")).peerDependencies?.["@earendil-works/pi-ai"] ?? ""; } catch {}
console.log(`PEER    @earendil-works/pi-ai ${peerVersion || "?"} ${peerPath}${declared ? ` (declared ${declared})` : ""}`);
if (declared.startsWith(">=") && peerVersion) {
	const want = declared.slice(2).split(".").map(Number), got = peerVersion.split(".").map(Number);
	if (got[0] < want[0] || (got[0] === want[0] && got[1] < want[1]) || (got[0] === want[0] && got[1] === want[1] && got[2] < want[2]))
		console.log(`ADVISORY peer ${peerVersion} does not satisfy the declared range ${declared} (advisory: a satisfying range can still be incompatible)`);
}
let rc = 0;
for (const rel of ["src/runs/background/subagent-runner.js", "src/watchdog/review.js"]) {
	const t0 = Date.now();
	try {
		await import(pathToFileURL(path.join(pkg, rel)).href);
		console.log(`IMPORT  ${rel} OK (${Date.now() - t0} ms)`);
	} catch (error) {
		rc = 1;
		console.log(`IMPORT  ${rel} FAILED: ${String(error.message).split("\n")[0]}`);
	}
}
process.exit(rc);
NODE
)"
	rc=$?
	while IFS= read -r line; do
		[ -n "$line" ] || continue
		case "$line" in
			ADVISORY\ *) warn_line "${line#ADVISORY }" ;;
			IMPORT\ *FAILED:*) fail RUNNER "${line#IMPORT  }" ;;
			*) report_line "$line" ;;
		esac
	done <<< "$out"
	if [ "$rc" -ne 0 ] && [ -z "$(printf '%s' "$failures" | awk '/^RUNNER$/{print;exit}')" ]; then
		fail RUNNER "runner import check exited $rc: $(printf '%s' "$out" | tail -n 1)"
	fi
}

# --- PATCHES: every marker, against the installed files --------------------------
marker_count() { # file pattern -> fixed-string match count
	[ -f "$1" ] || { printf '0\n'; return 0; }
	local n
	n="$(grep -cF -- "$2" "$1" 2>/dev/null)"
	[ -n "$n" ] || n=0
	printf '%s\n' "$n"
}

check_patches() {
	local name pkg patchfile spec item file pattern want got state ok saved_ifs
	if [ ! -f "$MANIFEST" ]; then
		fail PATCHES "manifest absent: $MANIFEST"
		return
	fi
	while IFS=$'\t' read -r name pkg patchfile spec; do
		case "${name:-}" in ''|'#'*) continue ;; esac
		state=""
		ok=1
		saved_ifs="$IFS"
		IFS=';'
		for item in $spec; do
			[ -n "$item" ] || continue
			file="${item%%|*}"
			pattern="${item#*|}"; pattern="${pattern%|*}"
			want="${item##*|}"
			got="$(marker_count "$pkg/$file" "$pattern")"
			state="$state $file:$got/$want"
			[ "$got" -ge "$want" ] 2>/dev/null || ok=0
		done
		IFS="$saved_ifs"
		if [ "$ok" -eq 1 ]; then
			report_line "PATCH   $name: applied ($state)"
		else
			fail PATCHES "$name: marker missing ($state)"
		fi
	done < "$MANIFEST"
}

check_host
check_runner
check_patches

if [ -n "$failures" ]; then
	printf '%s' "$report"
	[ "$verbose" -eq 1 ] && printf '%s' "$warnings"
	check="$(first_failure)"
	case "$check" in
		RUNNER) fix="pi update" ;;
		*) fix="bash $APPLIER" ;;
	esac
	body="check $check failed. Fix with: $fix
$(printf '%s' "$report" | tail -n 4)"
	notify "pi toolchain unhealthy: $check" "$body"
	if [ -n "${PI_DOCTOR_NO_NOTIFY:-}" ]; then
		printf 'notify (suppressed): pi toolchain unhealthy: %s | check %s failed. Fix with: %s\n' "$check" "$check" "$fix"
	fi
	exit 1
fi

if [ "$verbose" -eq 1 ]; then
	printf '%s' "$report"
	printf '%s' "$warnings"
	printf 'doctor: healthy\n'
fi
exit 0
