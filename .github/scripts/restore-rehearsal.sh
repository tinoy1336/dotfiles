#!/bin/sh
# restore-rehearsal — prove the committed set can rebuild a home directory.
#
# The repository's work tree is $HOME and its metadata lives outside it, so a
# clone hands over metadata only: the wrapper that pairs the two has to be
# installed before anything can be checked out, and it comes out of the clone
# itself. This rehearsal follows that order into a scratch directory and then
# verifies the result rather than trusting the exit status of the restore:
#
#   - the index matches the commit, file for file
#   - the number of files on disk matches the commit
#   - every tracked symlink carries the target it was committed with
#   - no path outside the tracked set appears, and status is quiet
#
# SAFETY. The wrapper derives both variables from $HOME, so a rehearsal that ran
# it unchanged would act on the live home directory — a `checkout` there discards
# uncommitted work anywhere in the tree. Every wrapper call below therefore runs
# under `HOME="$home"`, with the clone placed where the wrapper looks for it,
# `$HOME/.dotfiles.git`. The preflight before the first mutating call refuses to
# continue unless the wrapper resolves its git directory inside the scratch
# directory.
#
# Usage: restore-rehearsal.sh [repository]
#
# The scratch directory is removed on exit, whatever the outcome.

set -eu

src=${1:-.}
src=$(CDPATH= cd -- "$src" && pwd)

# With the bare layout the work tree is not a repository by itself, so a caller
# standing in it names the metadata instead: the argument wins when it is a
# repository in its own right, and GIT_DIR is the fallback.
if env -u GIT_DIR -u GIT_WORK_TREE git -C "$src" rev-parse --git-dir >/dev/null 2>&1; then
  :
elif [ -n "${GIT_DIR:-}" ] && git --git-dir="$GIT_DIR" rev-parse HEAD >/dev/null 2>&1; then
  src=$(CDPATH= cd -- "$GIT_DIR" && pwd)
else
  echo "restore-rehearsal: $src is not a git repository — name one, for example $HOME/.dotfiles.git" >&2
  exit 2
fi

work=$(mktemp -d)
home="$work/home"
wrapper="$work/dotfiles"
trap 'rm -rf "$work"' EXIT

mkdir -p "$home"
git clone --quiet --bare "$src" "$home/.dotfiles.git"
git --git-dir="$home/.dotfiles.git" show HEAD:.local/bin/dotfiles > "$wrapper"
chmod 0755 "$wrapper"

# One entry point for every wrapper call, with the scratch home in place of the
# real one. Nothing else in this script invokes the wrapper.
dotfiles() {
  HOME="$home" "$wrapper" "$@"
}

# git reads the pair the wrapper exports; the checks below run without it.
git_scratch() {
  GIT_DIR="$home/.dotfiles.git" GIT_WORK_TREE="$home" git "$@"
}

resolved=$(dotfiles rev-parse --absolute-git-dir)
case $resolved in
  "$home"/*) : ;;
  *)
    echo "restore-rehearsal: the wrapper resolves $resolved, outside the scratch tree — refusing" >&2
    exit 3
    ;;
esac

# Repo-local settings do not travel with a clone, so the rehearsal re-applies them
# exactly as a restore does.
dotfiles config feature.manyFiles true
dotfiles config core.fileMode true
dotfiles config core.autocrlf false
dotfiles config core.excludesFile "$home/.config/git/ignore"

# A clone carries no index, and the pathspec forms restore nothing from an empty
# index: `checkout -- .` matches no path and reports it. The restore reads the
# index from the commit and then writes the work tree from that index. Without
# `-f` a file already on disk is named and left alone, which is the behaviour a
# restore into a used home directory wants; the rehearsal starts from an empty
# tree, so every tracked path is expected to land.
dotfiles read-tree HEAD
dotfiles checkout-index -a

status=0
problem() {
  printf 'restore-rehearsal: %s\n' "$*" >&2
  status=1
}

expected=$(git_scratch ls-tree -r --name-only HEAD | wc -l | tr -d ' ')
checked_out=$(git_scratch ls-files | wc -l | tr -d ' ')
# The bare clone is the one thing in the scratch home that is not part of the
# restored set.
on_disk=$(find "$home" -mindepth 1 -not -path "$home/.dotfiles.git" -not -path "$home/.dotfiles.git/*" ! -type d | wc -l | tr -d ' ')

listing=$(mktemp)
committed=$(mktemp)
trap 'rm -rf "$work" "$listing" "$committed"' EXIT
git_scratch ls-files | sort > "$listing"
git_scratch ls-tree -r --name-only HEAD | sort > "$committed"
if ! diff -u "$committed" "$listing" >&2; then
  problem "the restored index differs from the commit"
fi

[ "$expected" = "$on_disk" ] ||
  problem "expected $expected path(s) on disk, found $on_disk"
[ "$expected" = "$checked_out" ] ||
  problem "expected $expected path(s) in the index, found $checked_out"

links=$(git_scratch ls-tree -r HEAD | grep '^120000' | cut -f2 || true)
link_count=0
for path in $links; do
  link_count=$((link_count + 1))
  [ -L "$home/$path" ] || { problem "$path is not a symlink after the restore"; continue; }
  want=$(git_scratch cat-file -p "HEAD:$path")
  got=$(readlink "$home/$path")
  [ "$want" = "$got" ] ||
    problem "$path points at '$got' instead of '$want'"
done

# A restored tree that carries the project tree or a path from before it was
# extracted is not a restore of this repository.
if git_scratch ls-files | grep -Eq '^\.config/ags/|^dev/tinshell/'; then
  problem "the tracked set names a path this repository does not carry"
fi

if [ -n "$(git_scratch status --porcelain -uall)" ]; then
  git_scratch status --short -uall >&2
  problem "status is not quiet in the restored tree"
fi

[ "$status" -eq 0 ] || exit 1

printf 'restore-rehearsal: %s path(s) restored, %s symlink(s) with their committed targets\n' \
  "$expected" "$link_count"
