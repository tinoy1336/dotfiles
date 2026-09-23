#!/bin/sh
# Lint every shell script this repository tracks, with shellcheck.
#
# The set comes from git rather than from a list here, so a script added to the
# repository is linted without editing this file. A finding fails the run unless
# the same file and check appear in shellcheck-allowlist.txt beside this script;
# that file records the findings the tree already carries, which makes a finding
# that is NOT recorded the only thing that can turn the job red.
#
# Usage: shellcheck.sh [path-to-shellcheck]
#
# With the bare metadata directory, git has to be pointed at the pair before this
# runs — the wrapper does that for its own calls, a caller of this script does it
# for this one:
#
#   export GIT_DIR="$HOME/.dotfiles.git" GIT_WORK_TREE="$HOME"

set -eu

# A relative path named on the command line would be resolved against an
# inherited CDPATH otherwise.
unset CDPATH

tool_missing() {
  echo "shellcheck: $check is not available — install shellcheck, or name one as the" >&2
  echo "shellcheck: first argument; THE LINT DID NOT RUN" >&2
  exit 2
}

# The checker is resolved BEFORE anything else runs. A missing checker lends
# nothing to the report, and an empty report reads exactly like a clean tree, so
# the run would print a finding count of none and pass. Resolve a path argument
# as an executable file and a bare name on PATH.
check=${1:-shellcheck}
case $check in
*/*) [ -x "$check" ] || { tool_missing; } ;;
*) command -v -- "$check" >/dev/null 2>&1 || { tool_missing; } ;;
esac

here=$(cd -- "$(dirname -- "$0")" && pwd)
allow="$here/shellcheck-allowlist.txt"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "shellcheck: not inside a git work tree — export GIT_DIR and GIT_WORK_TREE" >&2
  exit 2
}

list=$(mktemp)
report=$(mktemp)
pairs=$(mktemp)
trap 'rm -f "$list" "$report" "$pairs"' EXIT

# A shell script is a tracked regular file whose name ends in .sh or whose first
# line is a shebang naming a shell. A tracked symlink into a node bundle is
# neither, and is skipped before it is read.
git ls-files | while IFS= read -r path; do
  [ -L "$path" ] && continue
  case $path in
    *.sh) printf '%s\n' "$path"; continue ;;
  esac
  case $(head -n 1 "$path" 2>/dev/null) in
    '#!'*sh) printf '%s\n' "$path" ;;
  esac
done > "$list"

[ -s "$list" ] || { echo "shellcheck: no tracked shell script found" >&2; exit 2; }

# Warnings and errors both count; info and style notes do not. The checker's own
# status is read rather than discarded: 0 is a clean tree, 1 is findings, and
# anything else is the checker failing, which is not the same answer as a clean
# tree and must not be reported as one. The directive below suppresses the one
# unquoted expansion in this file and carries no trailing text: a comment after a
# directive is not part of it, and any line between it and the command it applies
# to would end its reach.
set +e
# shellcheck disable=SC2046
"$check" --format=gcc --severity=warning $(cat "$list") > "$report" 2>&1
run_status=$?
set -e

case $run_status in
0 | 1) ;;
*)
  cat "$report" >&2
  echo "shellcheck: $check exited $run_status — the lint did NOT complete" >&2
  exit "$run_status"
  ;;
esac

# gcc format is `path:line:col: severity: message [SCnnnn]`.
sed -n 's/^\([^:]*\):[0-9]*:[0-9]*: .*\[\(SC[0-9]*\)\]$/\1:\2/p' "$report" | sort -u > "$pairs"

# A run that reported findings but left no parsable line behind is a report the
# parse cannot read — the shape changed, or the output was not this format — so
# the finding count below would be a number derived from nothing.
if [ "$run_status" -ne 0 ] && [ ! -s "$pairs" ]; then
  cat "$report" >&2
  echo "shellcheck: $check reported findings but its report carried none this parse can read" >&2
  exit 1
fi

[ -f "$allow" ] || : > "$allow"
unexpected=$(grep -vxF -f "$allow" "$pairs" || true)

if [ -n "$unexpected" ]; then
  echo "shellcheck: findings this run has that $(basename "$allow") does not record:" >&2
  printf '%s\n' "$unexpected" >&2
  echo "shellcheck: full report" >&2
  cat "$report" >&2
  exit 1
fi

printf 'shellcheck: %s script(s) linted, %s finding(s) recorded\n' \
  "$(wc -l < "$list" | tr -d ' ')" "$(wc -l < "$pairs" | tr -d ' ')"
