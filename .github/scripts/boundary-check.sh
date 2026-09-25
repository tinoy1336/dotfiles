#!/bin/sh
# boundary-check — the tracked set may not carry the shell's own machinery.
#
# The shell repository owns the unit files its setup.sh renders and the promptd
# clients it links into ~/.local/bin. This repository carries what a restore
# writes into a home, so those paths are not tracked here. Fourteen of them left
# the tracked set for that reason, and nothing else in this repository would
# notice one coming back: shellcheck reads the tracked set for shell scripts, the
# portability gate reads it for path references, the palette gate reads it for
# rendered files and the rehearsal proves it can rebuild a home — none of them
# reads it for membership. A stray `git add -f`, a widened `.gitignore` negation
# or a new copy placed in one of those directories therefore passes every run.
#
# The list below is the boundary itself, taken from the inventory that decided the
# move, one path per line. A path on it that is tracked again fails the run.
#
# Usage: boundary-check.sh
#
# With the bare metadata directory, git has to be pointed at the pair before this
# runs:
#
#   export GIT_DIR="$HOME/.dotfiles.git" GIT_WORK_TREE="$HOME"

set -eu

# A relative path named on the command line would be resolved against an inherited
# CDPATH otherwise.
unset CDPATH

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "boundary-check: not inside a git work tree — export GIT_DIR and GIT_WORK_TREE" >&2
  exit 2
}

status=0
checked=0
while IFS= read -r path; do
  case $path in
  '' | '#'*) continue ;;
  esac
  checked=$((checked + 1))
  if git ls-files --error-unmatch -- "$path" >/dev/null 2>&1; then
    printf 'boundary-check: %s is tracked again\n' "$path" >&2
    printf 'boundary-check:   the shell repository owns that path and installs it with its setup.sh\n' >&2
    status=1
  fi
done <<'PATHS'
# the unit definitions the shell's setup.sh renders
.config/systemd/user/amdgpu-watch.service
.config/systemd/user/tinshell-islands-fallback.service
.config/systemd/user/tinshell-polkit.service
.config/systemd/user/tinshell-portal.service
.config/systemd/user/tinshell-promptd.service
.config/systemd/user/tinshell-shell.service
.config/systemd/user/tinshell-warm.service
# the promptd clients and the library they source
.local/bin/lib/promptd-client.sh
.local/bin/pinentry-promptd
.local/bin/prompt
.local/bin/ssh-askpass-promptd
.local/bin/sudo-approve-askpass
.local/bin/sudo-approve-password-cat
.local/bin/zenity
PATHS

[ "$status" -eq 0 ] || {
  echo "boundary-check: $checked path(s) checked, the tracked set carries one of them" >&2
  exit 1
}

printf 'boundary-check: %s path(s) checked, none of them tracked\n' "$checked"
