#!/bin/sh
# shellcheck — lint every shell script this repository tracks.
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

check=${1:-shellcheck}
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
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

# Warnings and errors both count; info and style notes do not. The command exits
# non-zero as soon as it reports anything, which is what the parse below reads.
# shellcheck disable=SC2046 # no tracked path contains whitespace
"$check" --format=gcc --severity=warning $(cat "$list") > "$report" 2>&1 || true

# gcc format is `path:line:col: severity: message [SCnnnn]`.
sed -n 's/^\([^:]*\):[0-9]*:[0-9]*: .*\[\(SC[0-9]*\)\]$/\1:\2/p' "$report" | sort -u > "$pairs"

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
