#!/bin/sh
# Gate: every file this repository renders from the house palette is current, and
# the palette it was rendered against is the one pinned here.
#
# The renderer is the published program palette-targets.json names, run through
# npx at the pinned version, so this script takes no renderer argument: a local
# run and the CI run are the same run. Set COLOURWAY_BIN to a local executable to
# run against a checkout of the renderer instead.
#
# Usage:
#
#   palette-check.sh            # compare; 1 when a file is stale
#   palette-check.sh --render   # re-render every target
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

command -v node >/dev/null 2>&1 || {
  echo "palette-check: node is not available — THE CHECK DID NOT RUN" >&2
  exit 2
}

here=$(cd -- "$(dirname -- "$0")" && pwd)

exec node "$here/palette-check.mjs" "$@"
