#!/usr/bin/env bash
# Self-test for apply-patches.sh, run against scratch copies of the packages.
#
# Scenario 1 (failure containment): a target whose surrounding code has moved must
#   fail loudly, exit non-zero, write the failure record, and leave every file
#   byte-identical.
# Scenario 2 (post-update recovery): pristine copies of every mirrored package must
#   be patched to bytes identical to the installed patched files, for every entry the
#   manifest registers. The mirror's manifest is built from the real one (names,
#   patch paths and marker specs; only the package directory is redirected), and its
#   file tree is seeded from the per-version pre-patch copies, so a newly registered
#   patch has to be mirrored here to be covered — the guard reports the mismatch when
#   it is not. A pre-patch copy that is not the packaged bytes of ITS version (a copy
#   of the previous version carried forward for a file assumed unchanged) fails here
#   as a mismatch against the installed file, which is the point: the seed has to be
#   the bytes the package shipped, not the bytes the previous one did.
# Scenario 3 (trigger coverage): every package directory the manifest names must appear
#   in the PathModified list the user manager reports for pi-patch-apply.path. A package
#   registered in the manifest with no watch entry on its directory is rewritten by npm
#   with nothing to fire the applier, so it lands unpatched and no other check here sees
#   it; this one fails and names the package.
#
# The test writes its own log and failure record into a temporary directory, so the
# real apply.log and FAILED are untouched, and package files outside the temporary
# directory are only ever read.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPLIER="$ROOT/apply-patches.sh"
NPM=/home/tinoy/.pi/agent/npm/node_modules
TODO_PKG="$NPM/@juicesharp/rpiv-todo"
SUB_PKG="$NPM/pi-subagents"
COST_PKG="$NPM/@tinoy/pi-deepseek-cost"
FLEET_PKG="$NPM/@tinoy/pi-fleet"
FIXTURES="$ROOT"

# The mirror is seeded from the per-version pre-patch copies — the bytes the installed
# package had before its patches were applied — so the versions are read from the packages
# themselves. A hard-coded version mirrors the previous release after an update, and every
# comparison below then fails for a reason that has nothing to do with the patches.
pkg_version() { # package dir -> its package.json version
	sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1/package.json" 2>/dev/null | head -n 1
}
TODO_SEED_VERSION="$(pkg_version "$TODO_PKG")"
SUB_SEED_VERSION="$(pkg_version "$SUB_PKG")"
COST_SEED_VERSION="$(pkg_version "$COST_PKG")"
FLEET_SEED_VERSION="$(pkg_version "$FLEET_PKG")"

SEED_FILES=(
	"$FIXTURES/rpiv-todo/pre-patch/index.ts.$TODO_SEED_VERSION"
	"$FIXTURES/pi-subagents/pre-patch/schemas.js.$SUB_SEED_VERSION"
	"$FIXTURES/pi-subagents/pre-patch/rpc.js.$SUB_SEED_VERSION"
	"$FIXTURES/pi-subagents/pre-patch/async-execution.js.$SUB_SEED_VERSION"
	"$FIXTURES/pi-subagents/pre-patch/subagent-executor.js.$SUB_SEED_VERSION"
	"$FIXTURES/pi-subagents/pre-patch/render.js.$SUB_SEED_VERSION"
	"$FIXTURES/pi-subagents/pre-patch/subagent-control.js.$SUB_SEED_VERSION"
	"$FIXTURES/pi-subagents/pre-patch/execution.js.$SUB_SEED_VERSION"
	"$FIXTURES/pi-subagents/pre-patch/subagent-runner.js.$SUB_SEED_VERSION"
	"$FIXTURES/pi-subagents/pre-patch/worker.md.$SUB_SEED_VERSION"
	"$FIXTURES/deepseek-cost/pre-patch/index.ts.$COST_SEED_VERSION"
	"$FIXTURES/fleet-output-discipline/pre-patch/section.ts.$FLEET_SEED_VERSION"
)
SEEDS_MISSING=""
for seed in "${SEED_FILES[@]}"; do
	[ -f "$seed" ] || SEEDS_MISSING="$SEEDS_MISSING $(basename "$seed")"
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
ok() { printf 'PASS  %s\n' "$1"; pass=$((pass + 1)); }
no() { printf 'FAIL  %s\n' "$1"; fail=$((fail + 1)); }
hash() { sha256sum "$1" | cut -d' ' -f1; }

run_applier() { # manifest -> stdout captured by the caller
	# The install-in-flight retry is timing, not containment: every package this test
	# writes was written moments ago by the test itself, so the window is switched off
	# and a deliberate failure still fails at once.
	PI_PATCH_MANIFEST="$1" PI_PATCH_LOG="$WORK/apply.log" PI_PATCH_FAILED="$WORK/FAILED" \
		PI_PATCH_NO_NOTIFY=1 PI_PATCH_RETRY_WINDOW=0 "$APPLIER"
}

# Entries scenario 2 mirrors, in the order the applier is to apply them. The list is
# this test's coverage: every entry the manifest registers for a package named here
# must appear, checked by the guard below.
MIRROR_ENTRIES="rpiv-todo-external-refresh pi-subagents-label-display pi-subagents-worker-board-name pi-subagents-resume-label pi-subagents-pause-aware-control deepseek-cost-two-unit-countdown fleet-output-discipline"

manifest_field() { # entry-name field-number
	awk -F'\t' -v n="$1" -v f="$2" '!/^#/ && $1 == n { print $f }' "$ROOT/managed-patches.conf"
}

mirror_conf_line() { # entry-name -> its manifest line with the package directory pointed at the mirror copy
	awk -F'\t' -v n="$1" -v root="$NPM" -v mirror="$WORK/mirror" '!/^#/ && $1 == n {
		dir = $2; sub("^" root, mirror, dir)
		printf "%s\t%s\t%s\t%s\n", $1, dir, $3, $4
	}' "$ROOT/managed-patches.conf"
}

# --- scenario 1: a moved target -------------------------------------------------
if [ -n "$SEEDS_MISSING" ]; then
	no "pristine seeds missing for the installed versions (rpiv-todo $TODO_SEED_VERSION, pi-subagents $SUB_SEED_VERSION, deepseek-cost $COST_SEED_VERSION, pi-fleet $FLEET_SEED_VERSION):$SEEDS_MISSING — run apply-patches.sh once after the update, then re-run this test"
	printf '\n%s: %s passed, %s failed\n' "$(basename "$0")" "$pass" "$fail"
	exit 1
fi
mkdir -p "$WORK/hostile/pkg"
cp -p "$FIXTURES/rpiv-todo/pre-patch/index.ts.$TODO_SEED_VERSION" "$WORK/hostile/pkg/index.ts"
awk '{ if ($0 ~ /makeTodoOverlayLoader\(importOverlay\)/) print "\t// target moved: this line is gone"; else print }' \
	"$WORK/hostile/pkg/index.ts" > "$WORK/hostile/pkg/index.ts.moved"
mv "$WORK/hostile/pkg/index.ts.moved" "$WORK/hostile/pkg/index.ts"
printf '{"name":"hostile-pkg","version":"9.9.9-selftest"}\n' > "$WORK/hostile/pkg/package.json"
printf 'hostile-target\t%s\t%s\tindex.ts|rpiv-todo:external-refresh|2\n' \
	"$WORK/hostile/pkg" "$ROOT/rpiv-todo/external-refresh.patch" > "$WORK/hostile.conf"

before="$(hash "$WORK/hostile/pkg/index.ts")"
if run_applier "$WORK/hostile.conf" > "$WORK/s1.out" 2>&1; then
	no "moved target must exit non-zero"
else
	ok "moved target exits non-zero"
fi
if [ "$(hash "$WORK/hostile/pkg/index.ts")" = "$before" ]; then
	ok "moved target is left byte-identical"
else
	no "moved target was modified"
fi
if [ -s "$WORK/FAILED" ]; then
	ok "failure record written: $(tr '\n' ' ' < "$WORK/FAILED")"
else
	no "no failure record"
fi
if grep -q 'Hunk #1 FAILED' "$WORK/apply.log"; then
	ok "apply.log carries the dry-run output"
else
	no "apply.log does not carry the dry-run output"
fi
if [ "$(grep -cF 'rpiv-todo:external-refresh' "$WORK/hostile/pkg/index.ts")" -eq 0 ]; then
	ok "no marker was written by the failed run"
else
	no "the failed run wrote a marker"
fi

# --- scenario 2: pristine packages (the post-update path) ----------------------
# One seed per target file of every mirrored entry: the pre-patch copy of the version
# the applier would find installed. The packages ship compiled .js sources, so the
# seeds (and the comparison below) name the .js files the patches and the markers do.
mkdir -p "$WORK/mirror/@juicesharp/rpiv-todo" "$WORK/mirror/@tinoy/pi-deepseek-cost" "$WORK/mirror/@tinoy/pi-fleet" "$WORK/mirror/pi-subagents/src/extension" \
	"$WORK/mirror/pi-subagents/src/runs/background" "$WORK/mirror/pi-subagents/src/runs/foreground" \
	"$WORK/mirror/pi-subagents/src/runs/shared" "$WORK/mirror/pi-subagents/src/tui" "$WORK/mirror/pi-subagents/agents"
cp -p "$FIXTURES/rpiv-todo/pre-patch/index.ts.$TODO_SEED_VERSION" "$WORK/mirror/@juicesharp/rpiv-todo/index.ts"
cp -p "$FIXTURES/pi-subagents/pre-patch/schemas.js.$SUB_SEED_VERSION" "$WORK/mirror/pi-subagents/src/extension/schemas.js"
cp -p "$FIXTURES/pi-subagents/pre-patch/rpc.js.$SUB_SEED_VERSION" "$WORK/mirror/pi-subagents/src/extension/rpc.js"
cp -p "$FIXTURES/pi-subagents/pre-patch/async-execution.js.$SUB_SEED_VERSION" "$WORK/mirror/pi-subagents/src/runs/background/async-execution.js"
cp -p "$FIXTURES/pi-subagents/pre-patch/subagent-executor.js.$SUB_SEED_VERSION" "$WORK/mirror/pi-subagents/src/runs/foreground/subagent-executor.js"
cp -p "$FIXTURES/pi-subagents/pre-patch/render.js.$SUB_SEED_VERSION" "$WORK/mirror/pi-subagents/src/tui/render.js"
cp -p "$FIXTURES/pi-subagents/pre-patch/subagent-control.js.$SUB_SEED_VERSION" "$WORK/mirror/pi-subagents/src/runs/shared/subagent-control.js"
cp -p "$FIXTURES/pi-subagents/pre-patch/execution.js.$SUB_SEED_VERSION" "$WORK/mirror/pi-subagents/src/runs/foreground/execution.js"
cp -p "$FIXTURES/pi-subagents/pre-patch/subagent-runner.js.$SUB_SEED_VERSION" "$WORK/mirror/pi-subagents/src/runs/background/subagent-runner.js"
cp -p "$FIXTURES/pi-subagents/pre-patch/worker.md.$SUB_SEED_VERSION" "$WORK/mirror/pi-subagents/agents/worker.md"
cp -p "$TODO_PKG/package.json" "$WORK/mirror/@juicesharp/rpiv-todo/package.json"
cp -p "$SUB_PKG/package.json" "$WORK/mirror/pi-subagents/package.json"
cp -p "$FIXTURES/deepseek-cost/pre-patch/index.ts.$COST_SEED_VERSION" "$WORK/mirror/@tinoy/pi-deepseek-cost/index.ts"
cp -p "$COST_PKG/package.json" "$WORK/mirror/@tinoy/pi-deepseek-cost/package.json"
cp -p "$FIXTURES/fleet-output-discipline/pre-patch/section.ts.$FLEET_SEED_VERSION" "$WORK/mirror/@tinoy/pi-fleet/section.ts"
cp -p "$FLEET_PKG/package.json" "$WORK/mirror/@tinoy/pi-fleet/package.json"
for name in $MIRROR_ENTRIES; do mirror_conf_line "$name"; done > "$WORK/mirror.conf"

# Coverage guard: the mirror must cover every entry the manifest registers for the
# packages it mirrors, and must not list an entry the manifest has dropped, and no
# registered entry may target a package this scenario cannot mirror. Without it a
# newly registered patch is silently uncovered — the mirror is patched by the entries
# it lists, so a target outside that list makes the comparison below fail with a
# message about the file rather than about the missing mirror entry.
mirror_pkgs="$(for name in $MIRROR_ENTRIES; do manifest_field "$name" 2; done | sort -u)"
covered="$(printf '%s\n' $MIRROR_ENTRIES | sort)"
registered="$(while read -r pkg; do
	awk -F'\t' -v p="$pkg" '!/^#/ && NF>=4 && $2 == p { print $1 }' "$ROOT/managed-patches.conf"
done <<< "$mirror_pkgs" | sort)"
unmirrored="$(awk -F'\t' -v pkgs="$mirror_pkgs" '
	BEGIN { n = split(pkgs, list, "\n"); for (i = 1; i <= n; i++) mirrored[list[i]] = 1 }
	!/^#/ && NF >= 4 && !($2 in mirrored) { print $1 " -> " $2 }' "$ROOT/managed-patches.conf")"
if [ -n "$unmirrored" ]; then
	no "registered entries outside the mirrored packages are not covered by this scenario: $(printf '%s' "$unmirrored" | tr '\n' '; ')"
elif [ -n "$mirror_pkgs" ] && [ "$covered" = "$registered" ]; then
	ok "mirror covers every entry registered for its packages ($(printf '%s' "$covered" | tr '\n' ' '))"
else
	no "mirror entry list and manifest disagree: covered [$(printf '%s' "$covered" | tr '\n' ' ')] vs registered [$(printf '%s' "$registered" | tr '\n' ' ')]"
fi

if run_applier "$WORK/mirror.conf" > "$WORK/s2.out" 2>&1; then
	ok "pristine mirror is patched (exit 0)"
else
	no "pristine mirror was not patched: $(tr '\n' ' ' < "$WORK/s2.out")"
fi
for pair in \
	"$WORK/mirror/@juicesharp/rpiv-todo/index.ts:$TODO_PKG/index.ts" \
	"$WORK/mirror/pi-subagents/src/extension/schemas.js:$SUB_PKG/src/extension/schemas.js" \
	"$WORK/mirror/pi-subagents/src/runs/background/async-execution.js:$SUB_PKG/src/runs/background/async-execution.js" \
	"$WORK/mirror/pi-subagents/src/runs/foreground/subagent-executor.js:$SUB_PKG/src/runs/foreground/subagent-executor.js" \
	"$WORK/mirror/pi-subagents/src/extension/rpc.js:$SUB_PKG/src/extension/rpc.js" \
	"$WORK/mirror/pi-subagents/src/runs/shared/subagent-control.js:$SUB_PKG/src/runs/shared/subagent-control.js" \
	"$WORK/mirror/pi-subagents/src/runs/foreground/execution.js:$SUB_PKG/src/runs/foreground/execution.js" \
	"$WORK/mirror/pi-subagents/src/runs/background/subagent-runner.js:$SUB_PKG/src/runs/background/subagent-runner.js" \
	"$WORK/mirror/pi-subagents/agents/worker.md:$SUB_PKG/agents/worker.md" \
	"$WORK/mirror/pi-subagents/src/tui/render.js:$SUB_PKG/src/tui/render.js" \
	"$WORK/mirror/@tinoy/pi-deepseek-cost/index.ts:$COST_PKG/index.ts" \
	"$WORK/mirror/@tinoy/pi-fleet/section.ts:$FLEET_PKG/section.ts"; do
	mirror="${pair%%:*}"
	installed="${pair#*:}"
	if [ "$(hash "$mirror")" = "$(hash "$installed")" ]; then
		ok "mirror matches the installed file: ${mirror#"$WORK/mirror/"}"
	else
		no "mirror differs from the installed file: ${mirror#"$WORK/mirror/"}"
	fi
done
for name in $MIRROR_ENTRIES; do
	if grep -qF " applied $name" "$WORK/apply.log"; then
		ok "mirror log records the apply of $name"
	else
		no "mirror log has no apply entry for $name"
	fi
done

# --- scenario 3: the trigger watches every patched package ---------------------
# Neither side is a list kept in this file: the package directories come from the manifest
# the applier reads, and the watch list is the one the user manager reports at this moment,
# because that is what really fires the applier — a unit file edited without a reload
# changes what the file says, not what the manager watches.
watch_paths() { # the PathModified entries systemd reports for the trigger
	timeout 15 systemctl --user show pi-patch-apply.path -p Paths 2>/dev/null |
		awk '/^Paths=.* \(PathModified\)$/ { sub(/^Paths=/, ""); sub(/ \(PathModified\)$/, ""); print }'
}

watched="$(watch_paths)"
if [ -z "$watched" ]; then
	no "the trigger's watch list could not be read (systemctl --user show pi-patch-apply.path -p Paths reported nothing — is the user manager running?)"
else
	unwatched="$(awk -F'\t' -v w="$watched" '
		BEGIN { n = split(w, list, "\n"); for (i = 1; i <= n; i++) watched[list[i]] = 1 }
		!/^#/ && NF >= 4 && !($2 in watched) { entries[$2] = entries[$2] (entries[$2] != "" ? "," : "") $1 }
		END { for (dir in entries) printf "%s [entries: %s]\n", dir, entries[dir] }
	' "$ROOT/managed-patches.conf" | sort)"
	if [ -n "$unwatched" ]; then
		no "the trigger does not watch every patched package: $(printf '%s' "$unwatched" | tr '\n' '; ') — add a PathModified= line for each of those directories to pi-patch-apply.path and reload the unit"
	else
		ok "the trigger watches every package directory the manifest names ($(printf '%s\n' "$watched" | wc -l) path entries)"
	fi
fi

printf '\n%s\n' "selftest: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
