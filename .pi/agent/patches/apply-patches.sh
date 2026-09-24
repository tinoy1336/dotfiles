#!/usr/bin/env bash
# Re-apply the local package patches recorded in managed-patches.conf.
#
# Contract:
#   - apply state is decided by grepping the INSTALLED files, never by a flag file;
#   - an already-patched package is a no-op: no patch run, no writes to the package;
#   - a patch is applied only when `patch --batch --dry-run` is clean against the
#     installed tree; a failure while that tree was written moments ago is an install
#     still in flight, so the dry run is retried while the package keeps changing and
#     only a settled tree can fail;
#   - the patch is then applied to copies in a staging directory and each patched
#     copy is renamed over its original, so a failure cannot leave a half-patched
#     package and a concurrent reader never sees a torn file;
#   - before renaming, the current files are copied to
#     <patch-dir>/pre-patch/<name>.<package-version> for a later rollback;
#   - any failure is appended to apply.log, copied to FAILED, and notified.
set -u

PATCH_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${PI_PATCH_MANIFEST:-$PATCH_ROOT/managed-patches.conf}"
LOG="${PI_PATCH_LOG:-$PATCH_ROOT/apply.log}"
FAILED="${PI_PATCH_FAILED:-$PATCH_ROOT/FAILED}"
LOCK="$PATCH_ROOT/.apply.lock"
MAX_LOG_LINES=2000
# An install in flight: the path unit fires on the first write of a package rewrite, so a
# failed dry run against a tree written moments ago is a race with npm, not a stale patch.
# The entry is retried while the package stays recently written, and reported only once the
# tree has settled and the patch still does not apply.
RECENT_WINDOW="${PI_PATCH_RETRY_WINDOW:-90}"
TRANSIENT_ATTEMPTS="${PI_PATCH_RETRY_ATTEMPTS:-4}"
TRANSIENT_WAIT="${PI_PATCH_RETRY_WAIT:-15}"
NOTIFY_APP="pi-patches"
# The toolchain doctor runs at the end of the run, so the one unit that already fires on
# every package rewrite and at every login covers both halves of "is this healthy?": the
# patches below, and the runner's ability to import its peers (a rewrite can leave every
# patch applied and the async runner dead at import).
DOCTOR="${PI_PATCH_DOCTOR:-$PATCH_ROOT/doctor.sh}"

now() { date '+%Y-%m-%d %H:%M:%S'; }
log() { printf '%s %s\n' "$(now)" "$*" >> "$LOG" 2>/dev/null || true; }
say() { log "$*"; printf '%s\n' "$*"; }

# The log is the durable record; the journal is the fallback when it cannot be written.
prepare_log() {
	if touch "$LOG" 2>/dev/null; then
		return 0
	fi
	printf 'warning: cannot write %s; progress goes to the journal only\n' "$LOG" >&2
	return 1
}

trim_log() {
	local lines
	lines=$(wc -l < "$LOG" 2>/dev/null || printf '0')
	if [ "$lines" -gt "$MAX_LOG_LINES" ]; then
		tail -n 1000 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
	fi
}

notify() { # urgency title body
	[ -n "${PI_PATCH_NO_NOTIFY:-}" ] && return 0
	command -v notify-send >/dev/null 2>&1 || return 0
	notify-send -a "$NOTIFY_APP" -u "$1" "$2" "$3" >/dev/null 2>&1 || true
}

marker_count() { # file pattern -> number of fixed-string matches
	[ -f "$1" ] || { printf '0\n'; return 0; }
	grep -cF -- "$2" "$1" 2>/dev/null || printf '0\n'
}

# Does the tree satisfy every marker of `spec`? spec = file|pattern|count;file|pattern|count
markers_ok() { # root spec
	local root="$1" spec="$2" item file pattern want got
	local IFS=';'
	for item in $spec; do
		[ -n "$item" ] || continue
		file="${item%%|*}"
		pattern="${item#*|}"; pattern="${pattern%|*}"
		want="${item##*|}"
		got="$(marker_count "$root/$file" "$pattern")"
		[ "$got" -ge "$want" ] 2>/dev/null || return 1
	done
	return 0
}

marker_state() { # root spec -> "path:pattern=got/expected" list
	local root="$1" spec="$2" item file pattern want got out=""
	local IFS=';'
	for item in $spec; do
		[ -n "$item" ] || continue
		file="${item%%|*}"
		pattern="${item#*|}"; pattern="${pattern%|*}"
		want="${item##*|}"
		got="$(marker_count "$root/$file" "$pattern")"
		out="$out $file:$got/$want"
	done
	printf '%s\n' "${out# }"
}

patch_targets() { # patch file -> target paths relative to the patched root
	grep '^+++ b/' "$1" | sed -e 's|^+++ b/||' -e 's/[[:space:]].*$//'
}

package_version() { # package dir
	sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1/package.json" 2>/dev/null | head -n 1
}

# Was this package written within RECENT_WINDOW seconds? A tree still being unpacked makes a
# dry-run failure transient; a settled tree makes it a real one.
package_recently_written() { # package dir
	local ref found
	ref="$(mktemp "${TMPDIR:-/tmp}/pi-patch-ref.XXXXXX")" || return 1
	if ! touch -d "-${RECENT_WINDOW} seconds" "$ref" 2>/dev/null; then
		rm -f "$ref"
		return 1
	fi
	found="$(find "$1" -maxdepth 2 -newer "$ref" -print -quit 2>/dev/null)"
	rm -f "$ref"
	[ -n "$found" ]
}

STAGE=""
cleanup() { [ -n "$STAGE" ] && rm -rf "$STAGE"; }
trap cleanup EXIT

failures=0
restored=0
failed_written=0
applied_names=""

# FAILED describes the whole run, so the first record creates it and later ones append
# instead of replacing the earlier finding.
write_failed() {
	if [ "$failed_written" -eq 0 ]; then
		failed_written=1
		cat > "$FAILED"
	else
		cat >> "$FAILED"
	fi
}

record_failure() { # name reason detail
	local name="$1" reason="$2" detail="${3:-}"
	{
		printf 'FAILED %s: %s\n' "$name" "$reason"
		[ -n "$detail" ] && printf '%s\n' "$detail" | sed 's/^/    /'
	} >> "$LOG"
	{
		printf '%s: %s\n' "$name" "$reason"
		printf 'detail: %s\n' "$LOG"
	} | write_failed
	failures=$((failures + 1))
	say "FAILED $name: $reason"
	notify critical "pi patch NOT applied: $name" "$reason
$(printf '%s' "$detail" | tail -n 3)"
}

apply_entry() { # name package-dir patch-file marker-spec
	local name="$1" pkg="$2" patchfile="$3" spec="$4"
	local entry_dir version file dryout dryrc applyout applyrc tmp attempt

	if [ ! -d "$pkg" ]; then
		record_failure "$name" "package directory absent: $pkg" ""
		return
	fi
	if [ ! -f "$patchfile" ]; then
		record_failure "$name" "patch file absent: $patchfile" ""
		return
	fi
	if markers_ok "$pkg" "$spec"; then
		say "ok      $name: already applied, no-op ($(marker_state "$pkg" "$spec"))"
		return
	fi

	entry_dir="$(dirname "$patchfile")"
	version="$(package_version "$pkg")"
	[ -n "$version" ] || version="unknown"

	# 1. validate against the installed tree; a failed dry run stops here.
	# --fuzz=0 requires an exact context match: a target whose surrounding code
	# moved is a failure to report, not something to paper over with a fuzzy apply.
	# A failure while the package was written moments ago is an install still in
	# flight -- the trigger fires on the first write of a rewrite and npm has not
	# finished writing the targets -- so the entry is retried while the tree stays
	# fresh, and reported only once it has settled and still does not apply.
	attempt=1
	while :; do
		dryout="$(patch -p1 --batch --fuzz=0 --dry-run -d "$pkg" < "$patchfile" 2>&1)"
		dryrc=$?
		[ "$dryrc" -eq 0 ] && break
		if [ "$attempt" -ge "$TRANSIENT_ATTEMPTS" ] || ! package_recently_written "$pkg"; then
			record_failure "$name" "dry run failed against $pkg (exit $dryrc)" "$dryout"
			return
		fi
		log "retry $name: package written within ${RECENT_WINDOW}s, install still in flight (attempt $attempt)"
		attempt=$((attempt + 1))
		sleep "$TRANSIENT_WAIT"
	done

	# 2. apply to a staging copy of every target file
	STAGE="$(mktemp -d "${TMPDIR:-/tmp}/pi-patch-apply.XXXXXX")" || {
		record_failure "$name" "cannot create staging directory" ""
		return
	}
	while IFS= read -r file; do
		[ -n "$file" ] || continue
		if [ ! -f "$pkg/$file" ]; then
			record_failure "$name" "patch target absent from $pkg: $file" ""
			return
		fi
		mkdir -p "$STAGE/$(dirname "$file")"
		cp -p "$pkg/$file" "$STAGE/$file"
	done <<< "$(patch_targets "$patchfile")"

	applyout="$(patch -p1 --batch --fuzz=0 -d "$STAGE" < "$patchfile" 2>&1)"
	applyrc=$?
	if [ "$applyrc" -ne 0 ] || ! markers_ok "$STAGE" "$spec"; then
		record_failure "$name" "staged apply failed (exit $applyrc)" "$applyout"
		return
	fi

	# 3. keep a per-version rollback copy, then rename the patched copies into place
	while IFS= read -r file; do
		[ -n "$file" ] || continue
		mkdir -p "$entry_dir/pre-patch"
		cp -p -n "$pkg/$file" "$entry_dir/pre-patch/$(basename "$file").$version"
		tmp="$pkg/$file.pi-apply.$$"
		if ! { cp "$STAGE/$file" "$tmp" && mv -f "$tmp" "$pkg/$file"; }; then
			rm -f "$tmp"
			record_failure "$name" "install of $file failed" ""
			return
		fi
	done <<< "$(patch_targets "$patchfile")"

	if ! markers_ok "$pkg" "$spec"; then
		record_failure "$name" "marker absent after install ($(marker_state "$pkg" "$spec"))" ""
		return
	fi

	restored=$((restored + 1))
	applied_names="$applied_names${applied_names:+, }$name"
	say "applied $name (version $version, rollback copies in $entry_dir/pre-patch)"
}

exec 9>"$LOCK"
if ! flock -n 9; then
	say "another apply run holds the lock; nothing done"
	exit 0
fi

prepare_log || true
trim_log
if [ ! -f "$MANIFEST" ]; then
	record_failure "manifest" "manifest absent: $MANIFEST" ""
	exit 1
fi

entries=0
while IFS=$'\t' read -r name pkg patchfile spec; do
	case "${name:-}" in ''|'#'*) continue ;; esac
	entries=$((entries + 1))
	apply_entry "$name" "$pkg" "$patchfile" "$spec"
done < "$MANIFEST"

# One notification per run covers every entry this run re-applied: an update rewrites
# several packages at once, and a popup per entry buries the ones that matter.
if [ "$restored" -gt 0 ]; then
	notify normal "pi patches re-applied: $restored" "$applied_names"
fi

# The doctor verdict closes the run. It reports only when unhealthy, and it is told to
# stay silent (while still printing the notification it would have sent, for the log)
# when this run already has a failure of its own to announce — one notification per run.
doctor_no_notify=""
if [ -n "${PI_PATCH_NO_NOTIFY:-}" ] || [ "$failures" -gt 0 ]; then
	doctor_no_notify="PI_DOCTOR_NO_NOTIFY=1"
fi
doctor_rc=0
if [ -f "$DOCTOR" ]; then
	DOCTOR_OUT="$(mktemp "${TMPDIR:-/tmp}/pi-doctor.XXXXXX")"
	env $doctor_no_notify PI_DOCTOR_MANIFEST="$MANIFEST" timeout 45 bash "$DOCTOR" > "$DOCTOR_OUT" 2>&1 || doctor_rc=$?
	while IFS= read -r line; do
		[ -n "$line" ] && say "doctor: $line"
	done < "$DOCTOR_OUT"
	rm -f "$DOCTOR_OUT"
elif [ -n "$DOCTOR" ]; then
	doctor_rc=1
	say "FAILED doctor: $DOCTOR absent"
fi
if [ "$doctor_rc" -ne 0 ]; then
	failures=$((failures + 1))
	{
		printf 'doctor: pi toolchain check failed (exit %s)\n' "$doctor_rc"
		printf 'detail: %s\n' "$LOG"
	} | write_failed
fi

if [ "$failures" -eq 0 ]; then
	rm -f "$FAILED"
	say "run complete: $entries managed, $restored applied now, 0 failures"
	exit 0
fi
say "run complete: $entries managed, $restored applied now, $failures FAILED (see $FAILED and $LOG)"
exit 1
