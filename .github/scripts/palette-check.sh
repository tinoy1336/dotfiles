#!/bin/sh
# Gate: every file this repository renders from the house palette is current, and
# the palette it was rendered against is the one pinned here.
#
# The renderer belongs to the palette repository and is not vendored into this
# one, so it is named as an argument (or in PALETTE_RENDERER) rather than
# guessed: a path baked into this file would be a checkout location no reader
# has. The target list, and the palette revision and digest every run is held
# to, are in palette-targets.json beside this script; the work is in
# palette-check.mjs, as it is for the portability job.
#
# Usage:
#
#   palette-check.sh <path-to-render>            # compare; 1 when a file is stale
#   palette-check.sh <path-to-render> --render   # re-render every target
#
# Render one target's own way and read the diff, or re-render the whole set and
# commit what moved; both are the same command with the check flag left off.
#
# With the bare metadata directory, git has to be pointed at the pair before this
# runs:
#
#   export GIT_DIR="$HOME/.dotfiles.git" GIT_WORK_TREE="$HOME"

set -eu

# A relative path named on the command line would be resolved against an
# inherited CDPATH otherwise.
unset CDPATH

renderer=${1:-${PALETTE_RENDERER:-}}
if [ $# -gt 0 ]; then
  shift
fi

# The renderer is resolved BEFORE anything else runs. A missing renderer lends
# nothing to the report, and an empty report reads exactly like a clean tree, so
# the run would print no drift and pass. A path argument is checked as an
# executable file, a bare name on PATH.
case $renderer in
"")
  echo "palette-check: name the palette renderer as the first argument, or set PALETTE_RENDERER" >&2
  echo "palette-check: THE CHECK DID NOT RUN" >&2
  exit 2
  ;;
*/*) [ -x "$renderer" ] || {
  echo "palette-check: $renderer is not an executable file — THE CHECK DID NOT RUN" >&2
  exit 2
} ;;
*) command -v -- "$renderer" >/dev/null 2>&1 || {
  echo "palette-check: $renderer is not on PATH — THE CHECK DID NOT RUN" >&2
  exit 2
} ;;
esac

command -v node >/dev/null 2>&1 || {
  echo "palette-check: node is not available — THE CHECK DID NOT RUN" >&2
  exit 2
}

here=$(cd -- "$(dirname -- "$0")" && pwd)

exec node "$here/palette-check.mjs" --renderer "$renderer" "$@"
