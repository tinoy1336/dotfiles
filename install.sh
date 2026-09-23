#!/bin/sh
# install.sh — the repository's front door.
#
# The installer itself lives with the repository's other scripts, so there is
# one implementation, the CI jobs run the file a reader runs, and this only
# forwards to it:
#
#   ./install.sh <target-home> [options]
#
# Every argument is passed through untouched; options, behaviour and exit codes
# are the installer's own (see --help).
set -eu

self=$0
case "$self" in
*/*) ;;
*) self=$(command -v -- "$self") || {
  printf 'install.sh: cannot locate %s on PATH\n' "$0" >&2
  exit 3
} ;;
esac
here=$(CDPATH='' cd -- "$(dirname -- "$self")" && pwd)
installer="$here/.github/scripts/dotfiles-install.sh"

[ -x "$installer" ] || {
  printf 'install.sh: no installer at %s\n' "$installer" >&2
  exit 3
}

exec "$installer" "$@"
