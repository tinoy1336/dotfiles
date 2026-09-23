#!/bin/sh
# Gate: no tracked file may name where the shell's checkout happens to live, and
# no tracked file may name a runtime directory by a fixed uid.
#
# The rule and its detectors are in check-paths.mjs beside this script; this
# wrapper is what a CI job and a local run both invoke, the way every job in this
# repository runs a script rather than inlining its commands.
#
# This repository IS a machine's own configuration, so its own home directory is
# not a finding — the README documents that home as machine-specific and names
# the installer that substitutes it. Every other home, and any checkout path the
# README does not document, still is one. Accepted references are recorded with
# their reason in portability-allow.txt beside this script (the repository root
# is the live home directory, so the record lives here instead of there).
#
# Usage: portability.sh
#
# With the bare metadata directory, git has to be pointed at the pair before this
# runs:
#
#   export GIT_DIR="$HOME/.dotfiles.git" GIT_WORK_TREE="$HOME"

set -eu

unset CDPATH

here=$(cd -- "$(dirname -- "$0")" && pwd)
root=$(cd -- "$here/../.." && pwd)

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "portability: not inside a git work tree — export GIT_DIR and GIT_WORK_TREE" >&2
  exit 2
}

# A missing runtime lends nothing to the report, and an empty report reads exactly
# like a clean tree, so it is resolved before anything is scanned.
command -v node >/dev/null 2>&1 || {
  echo "portability: node is not available — THE CHECK DID NOT RUN" >&2
  exit 2
}

# The home this repository configures (the one its README documents as
# machine-specific and its installer substitutes).
owner_home=${DOTFILES_OWNER_HOME:-tinoy}

cd -- "$root"
exec node "$here/check-paths.mjs" --allow-owner-home="$owner_home" \
  --allow-file="$here/portability-allow.txt" "$@"
